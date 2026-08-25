//
//  HoldingsProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Trade.self, SyncMetadata.self, AccountBalance.self, MarginBalance.self, configurations: config)
}

private func seedTrades(in container: ModelContainer) throws {
    let context = ModelContext(container)
    context.insert(Trade(
        binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
        price: 50000, quantity: 1.0, quoteQuantity: 50000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        isBuyer: true, orderId: 100
    ))
    context.insert(Trade(
        binanceTradeId: 2, symbol: "ETHUSDT", asset: "ETH",
        price: 3000, quantity: 5.0, quoteQuantity: 15000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_001_000),
        isBuyer: true, orderId: 101
    ))
    // Seed balances matching the traded quantities
    context.insert(AccountBalance(asset: "BTC", quantity: 1.0))
    context.insert(AccountBalance(asset: "ETH", quantity: 5.0))
    try context.save()
}

// MARK: - Initial State

@Suite("Given a HoldingsProcessor with initial state")
struct HoldingsInitTests {

    @Test("Then state has empty defaults")
    func initialState() throws {
        let container = try makeContainer()
        let processor = HoldingsProcessor(
            priceService: .noop,
            fifoCalculator: .live,
            modelContainer: container
        )
        #expect(processor.state.holdings.isEmpty)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }
}

// MARK: - Load Holdings

@Suite("Given a HoldingsProcessor loading holdings")
struct HoldingsLoadTests {

    @Test("When trades exist, then holdings are computed from SwiftData")
    func loadsFromSwiftData() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in
                ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0]
            }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        #expect(processor.state.holdings.count == 2)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }

    @Test("When no trades exist, then holdings list is empty")
    func emptyWhenNoTrades() async throws {
        let container = try makeContainer()
        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in [:] }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        #expect(processor.state.holdings.isEmpty)
        #expect(processor.state.isLoading == false)
    }

    @Test("When holdings are loaded, then they are sorted by value descending")
    func sortedByValue() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in
                ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0]
            }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        let assets = processor.state.holdings.map(\.asset)
        #expect(assets.first == "BTC") // 65000 > 17500
    }

    @Test("When price service fails, then error is set")
    func priceError() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in
                throw BinanceError.networkError(underlying: URLError(.timedOut))
            }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        #expect(processor.state.error != nil)
        #expect(processor.state.isLoading == false)
    }

    @Test("When asset has zero remaining quantity, then it is excluded")
    func zeroQuantityExcluded() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Buy then sell all
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 1.0, quoteQuantity: 60000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            isBuyer: false, orderId: 101
        ))
        try context.save()

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0] }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        #expect(processor.state.holdings.isEmpty)
    }

    @Test("When account balances are persisted, then quantity comes from the balance, not FIFO")
    func usesPersistedBalanceQuantity() async throws {
        let container = try makeContainer()
        try seedTrades(in: container) // BTC traded 1.0, ETH traded 5.0
        let context = ModelContext(container)
        context.insert(AccountBalance(asset: "BTC", quantity: 0.6))
        context.insert(AccountBalance(asset: "USDT", quantity: 1000))
        try context.save()

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 60000.0] }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        let btc = try #require(processor.state.holdings.first { $0.asset == "BTC" })
        #expect(btc.totalQuantity == 0.6) // wallet balance, not the traded 1.0
        let usdt = try #require(processor.state.holdings.first { $0.asset == "USDT" })
        #expect(usdt.totalQuantity == 1000)
        // ETH has trades but no balance row — excluded once balances are authoritative.
        #expect(processor.state.holdings.contains { $0.asset == "ETH" } == false)
    }
}

// MARK: - Concurrency Tests

@Suite("Given a HoldingsProcessor with concurrent FIFO computation")
struct HoldingsConcurrencyTests {

    @Test("When margin holdings are loaded, then FIFO is computed concurrently for each asset")
    func marginHoldingsFIFOComputedConcurrently() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Seed multiple cross-margin trades for different assets
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100,
            tradingMode: .crossMargin
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "ETHUSDT", asset: "ETH",
            price: 3000, quantity: 5.0, quoteQuantity: 15000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            isBuyer: true, orderId: 101,
            tradingMode: .crossMargin
        ))
        context.insert(CrossMarginBalance(asset: "BTC", borrowed: 0, free: 1.0, locked: 0, netAsset: 1.0, interest: 0))
        context.insert(CrossMarginBalance(asset: "ETH", borrowed: 0, free: 5.0, locked: 0, netAsset: 5.0, interest: 0))
        try context.save()

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0] }),
            fifoCalculator: .live,
            modelContainer: container,
            marginTradeImportService: .noop,
            marginBalanceService: MarginBalanceService(
                fetchCrossMarginAccount: { nil },
                fetchCrossMarginBalances: { [
                    CrossMarginBalance(asset: "BTC", borrowed: 0, free: 1.0, locked: 0, netAsset: 1.0, interest: 0),
                    CrossMarginBalance(asset: "ETH", borrowed: 0, free: 5.0, locked: 0, netAsset: 5.0, interest: 0),
                ] },
                fetchIsolatedMarginBalances: { _ in [] },
                fetchAllIsolatedMarginBalances: { [] }
            )
        )

        await processor.handle(.loadHoldings)

        // Both assets should have FIFO results computed
        let btcHolding = try #require(processor.state.holdings.first { $0.asset == "BTC" })
        let ethHolding = try #require(processor.state.holdings.first { $0.asset == "ETH" })
        #expect(btcHolding.totalQuantity == 1.0)
        #expect(ethHolding.totalQuantity == 5.0)
    }

    @Test("When FIFO computation runs concurrently, results match sequential computation")
    func concurrentFIFOMatchesSequentialResults() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)

        // Run through the processor (which uses concurrent FIFO)
        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0] }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadHoldings)

        // Verify FIFO P&L matches what sequential computation would produce
        // BTC: buy 1.0 @ 50k → remaining 1.0, cost basis 50k, unrealized = (65k-50k)*1.0 = 15k
        let btc = try #require(processor.state.holdings.first { $0.asset == "BTC" })
        #expect(btc.totalQuantity == 1.0)
        #expect(btc.unrealizedPnL == 15000.0)

        // ETH: buy 5.0 @ 3k → remaining 5.0, cost basis 15k, unrealized = (3.5k-3k)*5.0 = 2.5k
        let eth = try #require(processor.state.holdings.first { $0.asset == "ETH" })
        #expect(eth.totalQuantity == 5.0)
        #expect(eth.unrealizedPnL == 2500.0)
    }
}
