//
//  PriceAlertConfigTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given a PriceAlertConfig SwiftData model")
struct PriceAlertConfigTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self,
            configurations: config
        )
    }

    @Test("When created with only a symbol, then defaults are applied")
    func defaultsApplied() {
        let config = PriceAlertConfig(symbol: "BTCUSDT")

        #expect(config.symbol == "BTCUSDT")
        #expect(config.isEnabled == false)
        #expect(config.thresholdUSD == 100)
        #expect(config.lastNotifiedProfit == 0)
        #expect(config.lastNotifiedLoss == 0)
    }

    @Test("When created with explicit fields, then all properties are set")
    func creationWithExplicitFields() {
        let config = PriceAlertConfig(
            symbol: "ETHUSDT",
            isEnabled: true,
            thresholdUSD: 250,
            lastNotifiedProfit: 75
        )

        #expect(config.symbol == "ETHUSDT")
        #expect(config.isEnabled == true)
        #expect(config.thresholdUSD == 250)
        #expect(config.lastNotifiedProfit == 75)
    }

    @Test("When inserted into SwiftData, then it persists and can be fetched")
    @MainActor
    func persistenceRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, thresholdUSD: 100, lastNotifiedProfit: 0))
        try context.save()

        let descriptor = FetchDescriptor<PriceAlertConfig>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        let first = try #require(fetched.first)
        #expect(first.symbol == "BTCUSDT")
        #expect(first.isEnabled == true)
        #expect(first.thresholdUSD == 100)
    }

    @Test("When fetched by symbol, then returns the correct config")
    @MainActor
    func fetchBySymbol() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true))
        context.insert(PriceAlertConfig(symbol: "ETHUSDT", isEnabled: false))
        try context.save()

        let symbol = "ETHUSDT"
        let descriptor = FetchDescriptor<PriceAlertConfig>(
            predicate: #Predicate<PriceAlertConfig> { $0.symbol == symbol }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 1)
        #expect(results.first?.isEnabled == false)
    }

    @Test("When the baseline is updated, then save persists the change")
    @MainActor
    func updateBaseline() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let config = PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, lastNotifiedProfit: 0)
        context.insert(config)
        try context.save()

        config.lastNotifiedProfit = 100
        try context.save()

        let descriptor = FetchDescriptor<PriceAlertConfig>()
        let fetched = try context.fetch(descriptor)
        let first = try #require(fetched.first)
        #expect(first.lastNotifiedProfit == 100)
    }

    @Test("When the loss baseline is updated, then save persists the change")
    @MainActor
    func updateLossBaseline() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let config = PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true, lastNotifiedLoss: 0)
        context.insert(config)
        try context.save()

        config.lastNotifiedLoss = -250
        try context.save()

        let descriptor = FetchDescriptor<PriceAlertConfig>()
        let fetched = try context.fetch(descriptor)
        let first = try #require(fetched.first)
        #expect(first.lastNotifiedLoss == -250)
    }
}
