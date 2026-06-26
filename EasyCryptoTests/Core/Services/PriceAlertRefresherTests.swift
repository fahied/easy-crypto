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
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self,
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
}
