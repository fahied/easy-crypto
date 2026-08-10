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

private func seedTrades(in container: ModelContainer, mode: TradingMode = .spot) throws {
    let context = ModelContext(container)
    // BTC trades
    context.insert(Trade(
        binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
        price: 50000, quantity: 0.5, quoteQuantity: 25000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        isBuyer: true, orderId: 100,
        tradingMode: mode
    ))
    context.insert(Trade(
        binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
        price: 60000, quantity: 0.2, quoteQuantity: 12000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_200_000),
        isBuyer: false, orderId: 101,
        tradingMode: mode
    ))
    // ETH trade
    context.insert(Trade(
        binanceTradeId: 3, symbol: "ETHUSDT", asset: "ETH",
        price: 3000, quantity: 5.0, quoteQuantity: 15000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_100_000),
        isBuyer: true, orderId: 102,
        tradingMode: mode
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

    @Test("Then selectedTradingMode defaults to spot")
    func defaultTradingMode() throws {
        let container = try makeContainer()
        let processor = TradeHistoryProcessor(modelContainer: container)
        #expect(processor.state.selectedTradingMode == .spot)
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

// MARK: - Filter by Mode

@Suite("Given a TradeHistoryProcessor filtering by trading mode")
struct TradeHistoryModeFilterTests {

    @Test("When in spot mode, then only spot trades are loaded")
    func spotModeFiltersTrades() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        #expect(processor.state.selectedTradingMode == .spot)
        #expect(processor.state.trades.count == 6)
    }

    @Test("When filtering by crossMargin, then only crossMargin trades are loaded")
    func crossMarginModeFiltersTrades() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByMode(.crossMargin))

        #expect(processor.state.selectedTradingMode == .crossMargin)
        #expect(processor.state.trades.allSatisfy { $0.tradingModeEnum == .crossMargin })
        #expect(processor.state.trades.count == 3)
    }

    @Test("When filtering by isolatedMargin, then only isolatedMargin trades are loaded")
    func isolatedMarginModeFiltersTrades() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .isolatedMargin)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByMode(.isolatedMargin))

        #expect(processor.state.selectedTradingMode == .isolatedMargin)
        #expect(processor.state.trades.allSatisfy { $0.tradingModeEnum == .isolatedMargin })
        #expect(processor.state.trades.count == 3)
    }

    @Test("When switching to margin mode, then coin filter is cleared")
    func modeSwitchClearsCoinFilter() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByCoin("BTC"))
        await processor.handle(.filterByMode(.crossMargin))

        #expect(processor.state.selectedCoin == nil)
        #expect(processor.state.availableCoins == ["BTC", "ETH"])
    }

    @Test("When margin mode has sells with commission, then details show borrowingFee")
    func marginDetailsIncludeBorrowingFee() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Cross-margin buy
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 5, commissionAsset: "BTC",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100, tradingMode: .crossMargin
        ))
        // Cross-margin sell
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 55000, quantity: 0.5, quoteQuantity: 27500,
            commission: 2.75, commissionAsset: "BTC",
            timestamp: Date(timeIntervalSince1970: 1_700_200_000),
            isBuyer: false, orderId: 101, tradingMode: .crossMargin
        ))
        try context.save()

        let processor = TradeHistoryProcessor(modelContainer: container)
        await processor.handle(.loadHistory)

        let sellDetails = processor.state.details.filter { !$0.isBuyer }
        #expect(sellDetails.count == 1)
        let detail = sellDetails[0]
        #expect(detail.tradingMode == .crossMargin)
        #expect(detail.borrowingFee != nil)
        #expect(detail.marginAdjustedPnL != nil)
    }

    @Test("When in spot mode, then details have nil borrowingFee and marginAdjustedPnL")
    func spotDetailsHaveNoMarginFields() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        let sellDetails = processor.state.details.filter { !$0.isBuyer }
        #expect(sellDetails.count == 1)
        let detail = sellDetails[0]
        #expect(detail.tradingMode == .spot)
        #expect(detail.borrowingFee == nil)
        #expect(detail.marginAdjustedPnL == nil)
    }
}
