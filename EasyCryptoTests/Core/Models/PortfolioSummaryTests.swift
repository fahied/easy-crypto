//
//  PortfolioSummaryTests.swift
//  EasyCryptoTests
//

import Testing
@testable import EasyCrypto

@Suite("Given a PortfolioSummary value type")
struct PortfolioSummaryTests {

    @Test("When created with portfolio data, then all totals are set correctly")
    func creationWithValidData() {
        let summary = PortfolioSummary(
            totalInvestedUSDT: 100000.0,
            totalCurrentValueUSDT: 120000.0,
            totalUnrealizedPnL: 20000.0,
            totalUnrealizedPnLPercent: 20.0,
            totalRealizedPnL: 5000.0,
            holdingsCount: 5
        )

        #expect(summary.totalInvestedUSDT == 100000.0)
        #expect(summary.totalCurrentValueUSDT == 120000.0)
        #expect(summary.totalUnrealizedPnL == 20000.0)
        #expect(summary.totalUnrealizedPnLPercent == 20.0)
        #expect(summary.totalRealizedPnL == 5000.0)
        #expect(summary.holdingsCount == 5)
    }

    @Test("When portfolio is in loss, then unrealized P&L values are negative")
    func lossPortfolio() {
        let summary = PortfolioSummary(
            totalInvestedUSDT: 100000.0,
            totalCurrentValueUSDT: 80000.0,
            totalUnrealizedPnL: -20000.0,
            totalUnrealizedPnLPercent: -20.0,
            totalRealizedPnL: -3000.0,
            holdingsCount: 3
        )

        #expect(summary.totalUnrealizedPnL < 0)
        #expect(summary.totalUnrealizedPnLPercent < 0)
        #expect(summary.totalRealizedPnL < 0)
    }

    @Test("When portfolio is empty, then all values are zero")
    func emptyPortfolio() {
        let summary = PortfolioSummary.empty

        #expect(summary.totalInvestedUSDT == 0)
        #expect(summary.totalCurrentValueUSDT == 0)
        #expect(summary.totalUnrealizedPnL == 0)
        #expect(summary.totalUnrealizedPnLPercent == 0)
        #expect(summary.totalRealizedPnL == 0)
        #expect(summary.holdingsCount == 0)
    }

    @Test("When computed from holdings, then totals aggregate correctly")
    func computedFromHoldings() {
        let holdings = [
            Holding(
                asset: "BTC", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
                totalInvestedUSDT: 50000, currentPrice: 60000, currentValueUSDT: 60000,
                unrealizedPnL: 10000, unrealizedPnLPercent: 20, realizedPnL: 1000
            ),
            Holding(
                asset: "ETH", totalQuantity: 10.0, weightedAvgBuyPrice: 3000,
                totalInvestedUSDT: 30000, currentPrice: 3500, currentValueUSDT: 35000,
                unrealizedPnL: 5000, unrealizedPnLPercent: 16.67, realizedPnL: 500
            ),
        ]

        let summary = PortfolioSummary(from: holdings)

        #expect(summary.totalInvestedUSDT == 80000.0)
        #expect(summary.totalCurrentValueUSDT == 95000.0)
        #expect(summary.totalUnrealizedPnL == 15000.0)
        #expect(summary.totalRealizedPnL == 1500.0)
        #expect(summary.holdingsCount == 2)
    }

    @Test("When computed from holdings, then percent is based on total invested")
    func percentCalculation() {
        let holdings = [
            Holding(
                asset: "BTC", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
                totalInvestedUSDT: 50000, currentPrice: 55000, currentValueUSDT: 55000,
                unrealizedPnL: 5000, unrealizedPnLPercent: 10, realizedPnL: 0
            ),
        ]

        let summary = PortfolioSummary(from: holdings)

        // 5000 / 50000 * 100 = 10%
        #expect(summary.totalUnrealizedPnLPercent == 10.0)
    }

    @Test("When computed from empty holdings array, then returns empty summary")
    func computedFromEmptyHoldings() {
        let summary = PortfolioSummary(from: [])

        #expect(summary.totalInvestedUSDT == 0)
        #expect(summary.holdingsCount == 0)
    }
}
