//
//  HoldingsBalanceTests.swift
//  EasyCryptoTests
//
//  Tests for available vs locked balance display in Holdings.
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given a HoldingsProcessor loading spot holdings with free/locked balances")
struct HoldingsBalanceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Trade.self, SyncMetadata.self, AccountBalance.self, MarginBalance.self, CrossMarginBalance.self, configurations: config)
    }

    @Test("When spot asset has free and locked balances, then Holding carries available and locked values")
    func spotAvailableLockedDisplayed() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Seed trade so asset appears in holdings
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100
        ))
        // Seed account balance with free=0.6, locked=0.1
        context.insert(AccountBalance(asset: "BTC", quantity: 0.7))
        try context.save()

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0] }),
            fifoCalculator: .live,
            modelContainer: container,
            balanceService: BalanceService(
                fetchBalances: { [
                    "BTC": 0.7,  // free + locked
                ] }
            )
        )

        await processor.handle(.loadHoldings)

        let btc = try #require(processor.state.holdings.first { $0.asset == "BTC" })
        #expect(abs(btc.availableBalance - 0.6) < 1e-9, "availableBalance should be 0.6, got \(btc.availableBalance)")
        #expect(abs(btc.lockedBalance - 0.1) < 1e-9, "lockedBalance should be 0.1, got \(btc.lockedBalance)")
    }

    @Test("When spot asset has no locked balance, then locked is zero")
    func spotNoLocked() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Trade(
            binanceTradeId: 1, symbol: "ETHUSDT", asset: "ETH",
            price: 3000, quantity: 5.0, quoteQuantity: 15000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100
        ))
        context.insert(AccountBalance(asset: "ETH", quantity: 5.0))
        try context.save()

        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { _ in ["ETHUSDT": 3500.0] }),
            fifoCalculator: .live,
            modelContainer: container,
            balanceService: BalanceService(
                fetchBalances: { ["ETH": 5.0] }
            )
        )

        await processor.handle(.loadHoldings)

        let eth = try #require(processor.state.holdings.first { $0.asset == "ETH" })
        #expect(abs(eth.availableBalance - 5.0) < 1e-9)
        #expect(abs(eth.lockedBalance - 0.0) < 1e-9)
    }

    @Test("When pull-to-refresh is triggered, then loadHoldings intent is dispatched")
    func pullToRefreshTriggersLoadHoldings() async throws {
        let container = try makeContainer()
        try seedTrades(in: container)

        var didSync = false
        let processor = HoldingsProcessor(
            priceService: PriceService(fetchPrices: { symbols in
                Dictionary(uniqueKeysWithValues: symbols.map { ($0, 65000.0) })
            }),
            fifoCalculator: .live,
            modelContainer: container,
            balanceService: BalanceService(
                fetchBalances: {
                    didSync = true
                    return ["BTC": 1.0, "ETH": 5.0]
                }
            )
        )

        // Initial load
        await processor.handle(.loadPersisted)
        #expect(processor.state.holdings.count == 2)

        // Reset sync flag
        didSync = false

        // Trigger refresh (pull-to-refresh)
        await processor.handle(.loadHoldings)

        #expect(didSync == true, "loadHoldings should trigger a sync from exchange")
        #expect(processor.state.holdings.count == 2)
        #expect(processor.state.error == nil)
    }
}

// MARK: - Helpers

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
    context.insert(AccountBalance(asset: "BTC", quantity: 1.0))
    context.insert(AccountBalance(asset: "ETH", quantity: 5.0))
    try context.save()
}
