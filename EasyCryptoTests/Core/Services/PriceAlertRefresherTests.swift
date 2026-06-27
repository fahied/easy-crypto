//
//  PriceAlertRefresherTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given the PriceAlertRefresher")
@MainActor
struct PriceAlertRefresherTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self, NotificationLogEntry.self,
            configurations: config
        )
    }

    private func insertBTCBuy(_ context: ModelContext, price: Double, quantity: Double) {
        context.insert(Trade(
            binanceTradeId: 1,
            symbol: "BTCUSDT",
            asset: "BTC",
            price: price,
            quantity: quantity,
            quoteQuantity: price * quantity,
            commission: 0,
            commissionAsset: "USDT",
            timestamp: Date(),
            isBuyer: true,
            orderId: 1
        ))
    }

    private func alertService(price: Double) -> PriceAlertService {
        .live(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": price] }),
            fifoCalculator: .live,
            notificationService: .noop
        )
    }

    @Test("When an enabled alert fires, then the persisted baseline advances to current profit")
    func firesAndPersistsBaseline() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertBTCBuy(context, price: 50000, quantity: 1) // invested 50000; @60000 → profit 10000
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, thresholdUSD: 100, lastNotifiedProfit: 0))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 60000))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastNotifiedProfit == 10000)
    }

    @Test("When the only config is disabled, then nothing is persisted")
    func skipsDisabledConfig() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertBTCBuy(context, price: 50000, quantity: 1)
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: false, thresholdUSD: 100, lastNotifiedProfit: 0))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 60000))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastNotifiedProfit == 0)
    }

    @Test("When a loss alert fires, then the loss baseline advances and the profit baseline is untouched")
    func lossPersistsLossBaseline() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertBTCBuy(context, price: 50000, quantity: 1) // @49800 → profit -200
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, thresholdUSD: 100, lastNotifiedProfit: 0, lastNotifiedLoss: 0))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 49800))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastNotifiedLoss == -200)
        #expect(config.lastNotifiedProfit == 0)
    }

    @Test("When a percent-move alert fires, then the reference price resets to the current price")
    func percentMovePersistsReferencePrice() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PriceAlertConfig(
            symbol: "BTCUSDT",
            isEnabled: true,
            thresholdUSD: 100,
            percentThreshold: 5,
            referencePrice: 100000
        ))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 105000))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.referencePrice == 105000)
    }

    @Test("When the profit increase is below the threshold, then the baseline is unchanged")
    func belowThresholdLeavesBaseline() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertBTCBuy(context, price: 50000, quantity: 1) // @60000 → profit 10000
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, thresholdUSD: 100, lastNotifiedProfit: 9950))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 60000))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastNotifiedProfit == 9950)
    }

    @Test("When an alert fires, then a notification log entry is written for it")
    func firingWritesNotificationLogEntry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertBTCBuy(context, price: 50000, quantity: 1) // @60000 → profit 10000
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, thresholdUSD: 100, lastNotifiedProfit: 0))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 60000))

        let entries = try context.fetch(FetchDescriptor<NotificationLogEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.symbol == "BTCUSDT")
        #expect(entry.asset == "BTC")
        #expect(entry.direction == "gain")
        #expect(entry.value == 10000)
        #expect(entry.title == "BTC profit up")
    }

    @Test("When only the reference price is seeded silently, then no notification log entry is written")
    func silentSeedWritesNoLogEntry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        // No trades (profit 0) and a large USD threshold so gain/loss never fire;
        // referencePrice 0 triggers only the silent percent-reference seeding.
        context.insert(PriceAlertConfig(
            symbol: "BTCUSDT",
            isEnabled: true,
            thresholdUSD: 100,
            percentThreshold: 5,
            referencePrice: 0
        ))
        try context.save()

        try await PriceAlertRefresher.run(modelContext: context, alertService: alertService(price: 60000))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.referencePrice == 60000) // reference was seeded
        let entries = try context.fetch(FetchDescriptor<NotificationLogEntry>())
        #expect(entries.isEmpty) // but no notification was delivered, so nothing logged
    }
}
