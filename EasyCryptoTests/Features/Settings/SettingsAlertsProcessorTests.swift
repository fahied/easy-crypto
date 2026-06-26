//
//  SettingsAlertsProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given a SettingsProcessor managing price alerts")
@MainActor
struct SettingsAlertsProcessorTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self,
            configurations: config
        )
    }

    private func makeProcessor(
        container: ModelContainer,
        notificationService: NotificationService = .preview
    ) -> SettingsProcessor {
        SettingsProcessor(
            keychainService: KeychainService(save: { _, _ in }, load: { nil }, delete: { }),
            apiClient: .noop,
            modelContainer: container,
            notificationService: notificationService
        )
    }

    private func insertTrade(_ context: ModelContext, id: Int64, asset: String) {
        context.insert(Trade(
            binanceTradeId: id,
            symbol: "\(asset)USDT",
            asset: asset,
            price: 100,
            quantity: 1,
            quoteQuantity: 100,
            commission: 0,
            commissionAsset: "USDT",
            timestamp: Date(),
            isBuyer: true,
            orderId: id
        ))
    }

    @Test("When loading alerts, then a row is built per traded asset with defaults")
    func loadAlertsBuildsRows() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertTrade(context, id: 1, asset: "BTC")
        insertTrade(context, id: 2, asset: "ETH")
        try context.save()

        let processor = makeProcessor(container: container)
        await processor.handle(.loadAlerts)

        #expect(processor.state.alertRows.count == 2)
        let btc = processor.state.alertRows.first { $0.asset == "BTC" }
        #expect(btc?.symbol == "BTCUSDT")
        #expect(btc?.isEnabled == false)
        #expect(btc?.thresholdUSD == 100)
    }

    @Test("When enabling an alert, then the config is persisted and the row updates")
    func enablePersistsConfig() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertTrade(context, id: 1, asset: "BTC")
        try context.save()

        let processor = makeProcessor(container: container)
        await processor.handle(.loadAlerts)
        await processor.handle(.setAlertEnabled(symbol: "BTCUSDT", enabled: true))

        let configs = try context.fetch(FetchDescriptor<PriceAlertConfig>())
        #expect(configs.count == 1)
        #expect(configs.first?.isEnabled == true)
        #expect(processor.state.alertRows.first { $0.symbol == "BTCUSDT" }?.isEnabled == true)
    }

    @Test("When setting a threshold, then it is persisted and the row updates")
    func thresholdPersists() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertTrade(context, id: 1, asset: "BTC")
        try context.save()

        let processor = makeProcessor(container: container)
        await processor.handle(.loadAlerts)
        await processor.handle(.setAlertThreshold(symbol: "BTCUSDT", threshold: 250))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.thresholdUSD == 250)
        #expect(processor.state.alertRows.first { $0.symbol == "BTCUSDT" }?.thresholdUSD == 250)
    }

    @Test("When setting a percent threshold, then it is persisted and the row updates")
    func percentPersists() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertTrade(context, id: 1, asset: "BTC")
        try context.save()

        let processor = makeProcessor(container: container)
        await processor.handle(.loadAlerts)
        await processor.handle(.setAlertPercent(symbol: "BTCUSDT", percent: 10))

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.percentThreshold == 10)
        #expect(processor.state.alertRows.first { $0.symbol == "BTCUSDT" }?.percentThreshold == 10)
    }

    @Test("When requesting permission with a granting service, then state reflects authorized")
    func requestPermissionGranted() async throws {
        let processor = makeProcessor(container: try makeContainer(), notificationService: .preview)

        await processor.handle(.requestNotificationPermission)

        #expect(processor.state.notificationsAuthorized == true)
    }

    @Test("When requesting permission with a denying service, then state reflects unauthorized")
    func requestPermissionDenied() async throws {
        let processor = makeProcessor(container: try makeContainer(), notificationService: .noop)

        await processor.handle(.requestNotificationPermission)

        #expect(processor.state.notificationsAuthorized == false)
    }
}
