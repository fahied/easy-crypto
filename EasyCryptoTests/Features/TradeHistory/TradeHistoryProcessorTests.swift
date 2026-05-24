//
//  TradeHistoryProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
}

private func seedTrades(in container: ModelContainer) throws {
    let context = ModelContext(container)
    // BTC trades
    context.insert(Trade(
        binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
        price: 50000, quantity: 0.5, quoteQuantity: 25000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        isBuyer: true, orderId: 100
    ))
    context.insert(Trade(
        binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
        price: 60000, quantity: 0.2, quoteQuantity: 12000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_200_000),
        isBuyer: false, orderId: 101
    ))
    // ETH trade
    context.insert(Trade(
        binanceTradeId: 3, symbol: "ETHUSDT", asset: "ETH",
        price: 3000, quantity: 5.0, quoteQuantity: 15000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_100_000),
        isBuyer: true, orderId: 102
    ))
    try context.save()
}

// MARK: - Initial State

@Suite("Given a TradeHistoryProcessor with initial state")
struct TradeHistoryInitTests {

    @Test("Then state has empty defaults")
    func initialState() throws {
        let container = try makeContainer()
        let processor = TradeHistoryProcessor(modelContainer: container)
        #expect(processor.state.trades.isEmpty)
        #expect(processor.state.availableCoins.isEmpty)
        #expect(processor.state.selectedCoin == nil)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }
}

// MARK: - Load History

@Suite("Given a TradeHistoryProcessor loading history")
struct TradeHistoryLoadTests {

    @Test("When trades exist, then all trades are loaded reverse-chronologically")
    func loadsAllTrades() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        #expect(processor.state.trades.count == 3)
        #expect(processor.state.isLoading == false)
        // Reverse chronological: newest first
        let timestamps = processor.state.trades.map(\.timestamp)
        #expect(timestamps == timestamps.sorted(by: >))
    }

    @Test("When trades exist, then available coins are discovered and sorted")
    func discoversCoins() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        #expect(processor.state.availableCoins == ["BTC", "ETH"])
    }

    @Test("When no trades exist, then result is empty")
    func emptyHistory() async throws {
        let container = try makeContainer()
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        #expect(processor.state.trades.isEmpty)
        #expect(processor.state.availableCoins.isEmpty)
    }
}

// MARK: - Filter by Coin

@Suite("Given a TradeHistoryProcessor filtering by coin")
struct TradeHistoryFilterTests {

    @Test("When filtering by BTC, then only BTC trades are shown")
    func filterByBTC() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByCoin("BTC"))

        #expect(processor.state.trades.count == 2)
        #expect(processor.state.trades.allSatisfy { $0.asset == "BTC" })
        #expect(processor.state.selectedCoin == "BTC")
    }

    @Test("When filtering by ETH, then only ETH trades are shown")
    func filterByETH() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByCoin("ETH"))

        #expect(processor.state.trades.count == 1)
        #expect(processor.state.selectedCoin == "ETH")
    }

    @Test("When filter is cleared (nil), then all trades are shown again")
    func clearFilter() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByCoin("BTC"))
        await processor.handle(.filterByCoin(nil))

        #expect(processor.state.trades.count == 3)
        #expect(processor.state.selectedCoin == nil)
    }
}
