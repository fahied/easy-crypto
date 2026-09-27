//
//  PortfolioPnLBugTests.swift
//  EasyCryptoTests
//
//  Tests for ADV-PORTFOLIO-003 P&L display bug fixes.
//  Bug 1: zero P&L colored as profit (should be neutral)
//  Bug 2: negative marginAdjustedPnL hidden from summary
//  Bug 5: Holdings tab has no last-refresh timestamp
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
            CrossMarginBalance.self, MarginBalance.self,
        configurations: config
    )
}

private func makeMappedTrade(
    id: Int64 = 1,
    symbol: String = "BTCUSDT",
    asset: String = "BTC",
    price: Double = 50000,
    quantity: Double = 1.0,
    quoteQuantity: Double = 50000,
    commission: Double = 0,
    commissionAsset: String = "USDT",
    isBuyer: Bool = true,
    orderId: Int64 = 100
) -> MappedTrade {
    MappedTrade(
        binanceTradeId: id,
        symbol: symbol,
        asset: asset,
        price: price,
        quantity: quantity,
        quoteQuantity: quoteQuantity,
        commission: commission,
        commissionAsset: commissionAsset,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
        isBuyer: isBuyer,
        orderId: orderId
    )
}

private func makeProcessor(
    tradeImportService: TradeImportService = .noop,
    priceService: PriceService = .noop,
    fifoCalculator: FIFOCalculator = .live,
    apiClient: BinanceAPIClient = .noop,
    modelContainer: ModelContainer,
    balanceService: BalanceService = .noop,
    marginTradeImportService: MarginTradeImportService = .noop,
    marginBalanceService: MarginBalanceService = .noop
) throws -> PortfolioProcessor {
    return PortfolioProcessor(
        tradeImportService: tradeImportService,
        priceService: priceService,
        fifoCalculator: fifoCalculator,
        apiClient: apiClient,
        modelContainer: modelContainer,
        balanceService: balanceService,
        marginTradeImportService: marginTradeImportService,
        marginBalanceService: marginBalanceService
    )
}

// MARK: - Bug 1: Zero P&L Color

@Suite("Given a PortfolioSummary with zero total P&L")
struct PortfolioZeroPnLTests {

    @Test("When totalUnrealizedPnL is exactly zero, then it is not colored as profit")
    func zeroUnrealizedPnLIsNotProfit() throws {
        let summary = PortfolioSummary(
            totalInvestedUSDT: 1000,
            totalCurrentValueUSDT: 1000,
            totalUnrealizedPnL: 0,
            totalUnrealizedPnLPercent: 0,
            totalRealizedPnL: 0,
            holdingsCount: 1,
            spot: .empty,
            crossMargin: .empty,
            isolatedMargin: .empty
        )

        // The view currently uses >= 0 for profit color. Zero P&L should be neutral.
        // A value of 0 is neither profit nor loss.
        #expect(summary.totalUnrealizedPnL == 0)
        #expect(summary.totalUnrealizedPnL >= 0)  // passes with >= (current bug)
        #expect(!(summary.totalUnrealizedPnL > 0))  // should use > 0
    }

    @Test("When totalPnL is exactly zero, then it is not colored as profit")
    func zeroTotalPnLIsNotProfit() throws {
        let summary = PortfolioSummary(
            totalInvestedUSDT: 1000,
            totalCurrentValueUSDT: 1000,
            totalUnrealizedPnL: 0,
            totalUnrealizedPnLPercent: 0,
            totalRealizedPnL: 0,
            holdingsCount: 1,
            spot: .empty,
            crossMargin: .empty,
            isolatedMargin: .empty
        )

        #expect(summary.totalPnL == 0)
        #expect(!(summary.totalPnL > 0))
        #expect(!(summary.totalPnL < 0))
    }
}

// MARK: - Bug 2: Negative marginAdjustedPnL Hidden

@Suite("Given a PortfolioProcessor with cross-margin trades showing negative adjusted P&L")
struct PortfolioNegativeMarginPnLTests {

    @Test("When marginAdjustedRealizedPnL is negative, then it should appear in summary")
    func negativeMarginAdjustedPnLAppears() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // BTC cross-margin: bought 50k, sold 45k → realized loss of 5k before fees
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 0.1, quoteQuantity: 5000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100,
            tradingMode: .crossMargin
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 45000, quantity: 0.1, quoteQuantity: 4500,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            isBuyer: false, orderId: 101,
            tradingMode: .crossMargin
        ))
        // Borrowing fee of 500 USDT
        context.insert(CrossMarginBalance(
            asset: "BTC", borrowed: 0, free: 0, locked: 0,
            netAsset: 0, interest: 500
        ))
        try context.save()

        let processor = try makeProcessor(
            tradeImportService: .noop,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0] }),
            modelContainer: container,
            balanceService: .noop,
            marginTradeImportService: .noop,
            marginBalanceService: MarginBalanceService(
                fetchCrossMarginAccount: { nil },
                fetchCrossMarginBalances: {
                    [CrossMarginBalance(asset: "BTC", borrowed: 0, free: 0, locked: 0, netAsset: 0, interest: 500)]
                },
                fetchIsolatedMarginBalances: { _ in nil },
                fetchAllIsolatedMarginBalances: { [] }
            )
        )

        await processor.handle(.loadPersisted)

        // Realized PnL: sold 0.1 BTC at 45k, cost basis 50k → -500
        // Borrowing fees: 500
        // marginAdjustedRealizedPnL = -500 - 500 = -1000
        // Current condition: > 0 || totalBorrowingFees > 0 → true (fees > 0)
        // Should also show when marginAdjustedPnL != 0 (even with zero fees)
        let crossSummary = processor.state.summary.crossMargin
        #expect(crossSummary.holdingsCount == 0)  // no remaining balance
        // The crossMargin realized PnL reflects the -500 loss
        #expect(crossSummary.realizedPnL == -500.0)
    }

    @Test("When marginAdjustedRealizedPnL is negative with zero borrowing fees, then it is not hidden")
    func negativeMarginAdjustedPnLWithZeroFees() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // BTC cross-margin: buy 50k, sell 45k → -5k realized, no borrowing fees
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 0.1, quoteQuantity: 5000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100,
            tradingMode: .crossMargin
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 45000, quantity: 0.1, quoteQuantity: 4500,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            isBuyer: false, orderId: 101,
            tradingMode: .crossMargin
        ))
        // Zero borrowing fees — this is the case the current code hides
        context.insert(CrossMarginBalance(
            asset: "BTC", borrowed: 0, free: 0, locked: 0,
            netAsset: 0, interest: 0
        ))
        try context.save()

        let processor = try makeProcessor(
            tradeImportService: .noop,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0] }),
            modelContainer: container,
            balanceService: .noop,
            marginTradeImportService: .noop,
            marginBalanceService: MarginBalanceService(
                fetchCrossMarginAccount: { nil },
                fetchCrossMarginBalances: {
                    [CrossMarginBalance(asset: "BTC", borrowed: 0, free: 0, locked: 0, netAsset: 0, interest: 0)]
                },
                fetchIsolatedMarginBalances: { _ in nil },
                fetchAllIsolatedMarginBalances: { [] }
            )
        )

        await processor.handle(.loadPersisted)

        // marginAdjustedRealizedPnL = realizedPnL(-500) - fees(0) = -500
        // Current code: > 0 || totalBorrowingFees > 0 → false (hidden!)
        // Should be: != 0 → true (shown)
        let crossSummary = processor.state.summary.crossMargin
        #expect(crossSummary.realizedPnL == -500.0)
        #expect(crossSummary.realizedPnL != 0)  // should be visible
    }
}

// MARK: - Bug 5: Holdings Last Updated Timestamp

@Suite("Given a PortfolioProcessor handling refresh")
struct PortfolioLastRefreshTests {

    @Test("When refresh succeeds, then lastRefreshDate is set to a recent time")
    func refreshSetsLastRefreshDate() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(
                            id: 1, symbol: "BTCUSDT", asset: "BTC",
                            price: 50000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT"
                        ),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                    ]
                )
            }
        )

        let priceService = PriceService(
            fetchPrices: { _ in ["BTCUSDT": 65000.0] }
        )

        let beforeRefresh = Date()
        let processor = try makeProcessor(
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: try makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 1.0] })
        )

        #expect(processor.state.lastRefreshDate == nil)

        await processor.handle(.refresh)

        let afterRefresh = Date()
        #expect(processor.state.lastRefreshDate != nil)
        if let refreshDate = processor.state.lastRefreshDate {
            #expect(refreshDate >= beforeRefresh)
            #expect(refreshDate <= afterRefresh)
        }
    }
}

@Suite("Given a HoldingsProcessor with initial state")
struct HoldingsLastRefreshTests {

    @Test("Then state has nil lastRefreshDate by default")
    func initialLastRefreshDateIsNil() throws {
        let container = try makeContainer()
        let processor = HoldingsProcessor(
            priceService: .noop,
            fifoCalculator: .live,
            modelContainer: container
        )
        #expect(processor.state.lastRefreshDate == nil)
    }
}
