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

private func seedTrades(in container: ModelContainer, mode: TradingMode = .spot, idOffset: Int64 = 0) throws {
    let context = ModelContext(container)
    // BTC trades
    context.insert(Trade(
        binanceTradeId: 1 + idOffset, symbol: "BTCUSDT", asset: "BTC",
        price: 50000, quantity: 0.5, quoteQuantity: 25000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        isBuyer: true, orderId: 100 + idOffset,
        tradingMode: mode
    ))
    context.insert(Trade(
        binanceTradeId: 2 + idOffset, symbol: "BTCUSDT", asset: "BTC",
        price: 60000, quantity: 0.2, quoteQuantity: 12000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_200_000),
        isBuyer: false, orderId: 101 + idOffset,
        tradingMode: mode
    ))
    // ETH trade
    context.insert(Trade(
        binanceTradeId: 3 + idOffset, symbol: "ETHUSDT", asset: "ETH",
        price: 3000, quantity: 5.0, quoteQuantity: 15000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_100_000),
        isBuyer: true, orderId: 102 + idOffset,
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

// MARK: - Aggregation Across Trading Modes

@Suite("Given a TradeHistoryProcessor aggregating every trading mode")
struct TradeHistoryAggregationTests {

    @Test("When spot and margin trades exist, then all of them are loaded")
    func loadsEveryMode() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin, idOffset: 10)
        try seedTrades(in: container, mode: .isolatedMargin, idOffset: 20)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        #expect(processor.state.trades.count == 9)
        let modes = Set(processor.state.details.map(\.tradingMode))
        #expect(modes == [.spot, .crossMargin, .isolatedMargin])
    }

    @Test("When modes share a day, then daily P&L sums their realized P&L")
    func dailyPnLSumsAcrossModes() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin, idOffset: 10)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        let sellDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_200_000))
        let entry = try #require(processor.state.dailyPnL[sellDay])
        // Each mode contributes one sell of 0.2 BTC bought at 50k, sold at 60k → 2000 each.
        #expect(entry.sellCount == 2)
        #expect(abs(entry.realizedPnL - 4000) < 0.01)
    }

    @Test("When modes share an asset, then FIFO lots do not cross modes")
    func fifoIsolatedPerMode() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Spot buy at 50k, margin buy at 20k — the margin sell must consume the margin lot.
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100, tradingMode: .spot
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 20000, quantity: 1.0, quoteQuantity: 20000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_100_000),
            isBuyer: true, orderId: 101, tradingMode: .crossMargin
        ))
        context.insert(Trade(
            binanceTradeId: 3, symbol: "BTCUSDT", asset: "BTC",
            price: 30000, quantity: 1.0, quoteQuantity: 30000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_200_000),
            isBuyer: false, orderId: 102, tradingMode: .crossMargin
        ))
        try context.save()

        let processor = TradeHistoryProcessor(modelContainer: container)
        await processor.handle(.loadHistory)

        let sell = try #require(processor.state.details.first { !$0.isBuyer })
        #expect(sell.tradingMode == .crossMargin)
        #expect(abs((sell.realizedPnL ?? 0) - 10000) < 0.01)
    }

    @Test("When filtering by coin, then every mode for that coin is kept")
    func coinFilterSpansModes() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        try seedTrades(in: container, mode: .crossMargin, idOffset: 10)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)
        await processor.handle(.filterByCoin("BTC"))

        #expect(processor.state.trades.count == 4)
        #expect(Set(processor.state.details.map(\.tradingMode)) == [.spot, .crossMargin])
    }

    @Test("When margin sells carry commission, then details show borrowingFee")
    func marginDetailsIncludeBorrowingFee() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Cross-margin buy
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0.001, commissionAsset: "BTC",
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

    @Test("When trades are spot, then details have nil borrowingFee and marginAdjustedPnL")
    func spotDetailsHaveNoMarginFields() async throws {
        let container = try makeContainer()
        try seedTrades(in: container, mode: .spot)
        let processor = TradeHistoryProcessor(modelContainer: container)

        await processor.handle(.loadHistory)

        let sellDetails = processor.state.details.filter { !$0.isBuyer }
        #expect(sellDetails.count == 1)
        let detail = sellDetails[0]
        #expect(detail.tradingMode == .spot)
        #expect(detail.borrowingFee == 0.0)
        #expect(detail.marginAdjustedPnL == nil)
    }
}

// MARK: - Multi-fill Order Grouping

@Suite("Given a TradeHistoryProcessor with fills that span multiple days")
struct TradeHistoryMultiFillTests {

    /// A large sell order that Binance executed as two fills on different days.
    /// The aggregate should NOT collapse both fills into the later day.
    @Test("When a single order fills across two days, then both days show the sell")
    func multiFillOrderSpansDays() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // One buy so the FIFO lots exist.
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_699_000_000),
            isBuyer: true, orderId: 500, tradingMode: .spot
        ))

        // A sell order (orderId 501) that fills in two pieces on different days.
        // Fill 1 — Jan 2: sells 0.3 BTC at 60000
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 0.3, quoteQuantity: 18000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: false, orderId: 501, tradingMode: .spot
        ))
        // Fill 2 — Jan 3: sells 0.3 BTC at 60000 (same order)
        context.insert(Trade(
            binanceTradeId: 3, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 0.3, quoteQuantity: 18000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_864_000),
            isBuyer: false, orderId: 501, tradingMode: .spot
        ))
        try context.save()

        let processor = TradeHistoryProcessor(modelContainer: container)
        await processor.handle(.loadHistory)

        let sellDetails = processor.state.details.filter { !$0.isBuyer }
        #expect(sellDetails.count == 2, "Expected 2 sell entries (one per day), got \(sellDetails.count)")

        let day1 = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_864_000))

        let pnl1 = processor.state.dailyPnL[day1]?.realizedPnL ?? 0
        let pnl2 = processor.state.dailyPnL[day2]?.realizedPnL ?? 0
        let totalPnL = pnl1 + pnl2

        // Each sell: (60000 - 50000) * 0.3 = 3000. Total = 6000.
        #expect(abs(pnl1 - 3000) < 0.01, "Jan 2 P&L should be 3000, got \(pnl1)")
        #expect(abs(pnl2 - 3000) < 0.01, "Jan 3 P&L should be 3000, got \(pnl2)")
        #expect(abs(totalPnL - 6000) < 0.01, "Total P&L should be 6000, got \(totalPnL)")
    }
}
