//
//  SyncMetadataCompositeKeyTests.swift
//  EasyCryptoTests
//
//  Tests for the composite unique key [symbol, tradingMode] on SyncMetadata.

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given the SyncMetadata composite unique key [symbol, tradingMode]")
struct SyncMetadataCompositeKeyTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Trade.self, SyncMetadata.self, configurations: config
        )
    }

    @Test("When same symbol has different trading modes, then both persist")
    @MainActor
    func compositeKeyAllowsDifferentModes() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(SyncMetadata(
            symbol: "BTCUSDT", lastTradeId: 100, lastSyncDate: Date(),
            tradingMode: .spot
        ))
        context.insert(SyncMetadata(
            symbol: "BTCUSDT", lastTradeId: 200, lastSyncDate: Date(),
            tradingMode: .crossMargin
        ))
        context.insert(SyncMetadata(
            symbol: "BTCUSDT", lastTradeId: 300, lastSyncDate: Date(),
            tradingMode: .isolatedMargin
        ))
        try context.save()

        let descriptor = FetchDescriptor<SyncMetadata>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 3)

        let spotModes = fetched.filter { $0.tradingModeEnum == .spot }
        let crossModes = fetched.filter { $0.tradingModeEnum == .crossMargin }
        #expect(spotModes.count == 1)
        #expect(crossModes.count == 1)
    }

    @Test("When same symbol and same trading mode, then second insert replaces first")
    @MainActor
    func compositeKeyPreventsDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(SyncMetadata(
            symbol: "ETHUSDT", lastTradeId: 100, lastSyncDate: Date(),
            tradingMode: .spot
        ))
        context.insert(SyncMetadata(
            symbol: "ETHUSDT", lastTradeId: 200, lastSyncDate: Date(),
            tradingMode: .spot
        ))
        try context.save()

        let descriptor = FetchDescriptor<SyncMetadata>()
        let fetched = try context.fetch(descriptor)
        // Composite unique key means only one record survives for (ETHUSDT, spot)
        #expect(fetched.count == 1)
    }

    @Test("When tradingMode defaults, then persists as spot")
    @MainActor
    func defaultTradingModeIsSpot() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let metadata = SyncMetadata(
            symbol: "ADAUSDT", lastTradeId: 50, lastSyncDate: Date()
        )
        #expect(metadata.tradingModeEnum == .spot)

        context.insert(metadata)
        try context.save()

        let descriptor = FetchDescriptor<SyncMetadata>()
        let fetched = try context.fetch(descriptor)
        let first = try #require(fetched.first)
        #expect(first.tradingModeEnum == .spot)
    }
}
