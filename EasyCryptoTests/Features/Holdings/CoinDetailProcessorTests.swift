//
//  CoinDetailProcessorTests.swift
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

private func seedBTCTrades(in container: ModelContainer) throws {
    let context = ModelContext(container)
    context.insert(Trade(
        binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
        price: 50000, quantity: 0.5, quoteQuantity: 25000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        isBuyer: true, orderId: 100
    ))
    context.insert(Trade(
        binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
        price: 55000, quantity: 0.3, quoteQuantity: 16500,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_100_000),
        isBuyer: true, orderId: 101
    ))
    context.insert(Trade(
        binanceTradeId: 3, symbol: "BTCUSDT", asset: "BTC",
        price: 60000, quantity: 0.1, quoteQuantity: 6000,
        commission: 0, commissionAsset: "USDT",
        timestamp: Date(timeIntervalSince1970: 1_700_200_000),
        isBuyer: false, orderId: 102
    ))
    try context.save()
}

private let sampleKlines: [Kline] = [
    Kline(openTime: 1_700_000_000_000, open: 50000, high: 51000, low: 49000,
          close: 50500, volume: 1000, closeTime: 1_700_086_400_000),
    Kline(openTime: 1_700_086_400_000, open: 50500, high: 52000, low: 50000,
          close: 51500, volume: 1200, closeTime: 1_700_172_800_000),
]

private func makeProcessor(
    container: ModelContainer,
    prices: [String: Double] = ["BTCUSDT": 65000.0],
    klines: [Kline] = sampleKlines
) -> CoinDetailProcessor {
    CoinDetailProcessor(
        apiClient: BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in klines },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        ),
        priceService: PriceService(fetchPrices: { _ in prices }),
        fifoCalculator: .live,
        modelContainer: container
    )
}

// MARK: - Load Detail

@Suite("Given a CoinDetailProcessor loading detail")
struct CoinDetailLoadTests {

    @Test("When loadDetail is called, then holding is computed for the asset")
    func loadsHolding() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        let processor = makeProcessor(container: container)

        await processor.handle(.loadDetail(asset: "BTC"))

        let holding = try #require(processor.state.holding)
        #expect(holding.asset == "BTC")
        #expect(holding.totalQuantity == 0.7) // 0.5 + 0.3 - 0.1
        #expect(holding.currentPrice == 65000.0)
        #expect(processor.state.isLoading == false)
    }

    @Test("When loadDetail is called, then trades for that asset are loaded")
    func loadsTrades() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        let processor = makeProcessor(container: container)

        await processor.handle(.loadDetail(asset: "BTC"))

        #expect(processor.state.trades.count == 3)
        #expect(processor.state.asset == "BTC")
    }

    @Test("When loadDetail is called, then klines are fetched for chart")
    func loadsKlines() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        let processor = makeProcessor(container: container)

        await processor.handle(.loadDetail(asset: "BTC"))

        #expect(processor.state.klines.count == 2)
    }

    @Test("When loadDetail fails, then error is set")
    func loadError() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        let processor = CoinDetailProcessor(
            apiClient: BinanceAPIClient(
                fetchAccount: { [] },
                fetchMyTrades: { _, _ in [] },
                fetchTickerPrices: { _ in [] },
                fetchKlines: { _, _, _ in [] },
                fetchMarginAccount: {
                    BinanceMarginAccount(
                        marginLevel: "0", totalAssetOfBtc: "0",
                        totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                        totalAsset: "0", totalLiability: "0",
                        totalNetAsset: "0", maxBorrowable: "0",
                        maintained: nil, userAssets: []
                    )
                },
                fetchMarginMyTrades: { _, _, _ in [] },
                fetchMarginOpenOrders: { _, _ in [] },
                fetchMarginAllAssets: { [] },
                fetchIsolatedMarginTransfers: { _ in [] }
            ),
            priceService: PriceService(fetchPrices: { _ in
                throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet))
            }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadDetail(asset: "BTC"))

        #expect(processor.state.error != nil)
        #expect(processor.state.isLoading == false)
    }
}

// MARK: - Chart Interval

@Suite("Given a CoinDetailProcessor changing chart interval")
struct CoinDetailChartIntervalTests {

    @Test("When changeChartInterval is called, then interval is updated and klines refetched")
    func changesInterval() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        let processor = makeProcessor(container: container)

        await processor.handle(.loadDetail(asset: "BTC"))
        await processor.handle(.changeChartInterval(.oneHour))

        #expect(processor.state.chartInterval == .oneHour)
        #expect(processor.state.klines.count == 2)
    }

    @Test("When changeChartInterval is called with no asset loaded, then no fetch occurs")
    func noFetchWithoutAsset() async throws {
        let container = try makeContainer()
        var fetchCalled = false
        let processor = CoinDetailProcessor(
            apiClient: BinanceAPIClient(
                fetchAccount: { [] },
                fetchMyTrades: { _, _ in [] },
                fetchTickerPrices: { _ in [] },
                fetchKlines: { _, _, _ in
                    fetchCalled = true
                    return []
                },
                fetchMarginAccount: {
                    BinanceMarginAccount(
                        marginLevel: "0", totalAssetOfBtc: "0",
                        totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                        totalAsset: "0", totalLiability: "0",
                        totalNetAsset: "0", maxBorrowable: "0",
                        maintained: nil, userAssets: []
                    )
                },
                fetchMarginMyTrades: { _, _, _ in [] },
                fetchMarginOpenOrders: { _, _ in [] },
                fetchMarginAllAssets: { [] },
                fetchIsolatedMarginTransfers: { _ in [] }
            ),
            priceService: .noop,
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.changeChartInterval(.fourHour))

        #expect(processor.state.chartInterval == .fourHour)
        #expect(!fetchCalled)
    }

    @Test("When kline fetch fails on interval change, then error is set")
    func klineError() async throws {
        let container = try makeContainer()
        try seedBTCTrades(in: container)
        var callCount = 0
        let processor = CoinDetailProcessor(
            apiClient: BinanceAPIClient(
                fetchAccount: { [] },
                fetchMyTrades: { _, _ in [] },
                fetchTickerPrices: { _ in [] },
                fetchKlines: { _, _, _ in
                    callCount += 1
                    if callCount > 1 {
                        throw BinanceError.networkError(underlying: URLError(.timedOut))
                    }
                    return sampleKlines
                },
                fetchMarginAccount: {
                    BinanceMarginAccount(
                        marginLevel: "0", totalAssetOfBtc: "0",
                        totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                        totalAsset: "0", totalLiability: "0",
                        totalNetAsset: "0", maxBorrowable: "0",
                        maintained: nil, userAssets: []
                    )
                },
                fetchMarginMyTrades: { _, _, _ in [] },
                fetchMarginOpenOrders: { _, _ in [] },
                fetchMarginAllAssets: { [] },
                fetchIsolatedMarginTransfers: { _ in [] }
            ),
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0] }),
            fifoCalculator: .live,
            modelContainer: container
        )

        await processor.handle(.loadDetail(asset: "BTC"))
        await processor.handle(.changeChartInterval(.oneWeek))

        #expect(processor.state.error != nil)
    }
}

// MARK: - Initial State

@Suite("Given a CoinDetailProcessor with initial state")
struct CoinDetailInitTests {

    @Test("Then state has empty defaults")
    func initialState() throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)
        #expect(processor.state.asset == "")
        #expect(processor.state.holding == nil)
        #expect(processor.state.trades.isEmpty)
        #expect(processor.state.klines.isEmpty)
        #expect(processor.state.chartInterval == .oneDay)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }
}
