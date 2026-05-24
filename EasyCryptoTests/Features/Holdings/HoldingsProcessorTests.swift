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
    return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
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
}
