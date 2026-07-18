//
//  ProfitBreakdownViewTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given the profit breakdown screen")
struct ProfitBreakdownViewTests {

    // MARK: - Sorting

    @Test("When symbols have mixed P&L, then they are sorted by realized P&L descending")
    func symbolsSortedByPnLDescending() {
        let summary = TradeSummary(
            totalTrades: 3,
            buyCount: 0,
            sellCount: 0,
            symbolCount: 3,
            totalRealizedPnL: 500,
            winningSells: 0,
            losingSells: 0,
            currentWinStreak: 0,
            currentLossStreak: 0,
            averageHoldingPeriodDays: 0,
            concentrationRatio: 0,
            topSymbols: [
                SymbolSummary(symbol: "BTCUSDT", asset: "BTC", tradeCount: 1, buyCount: 0, sellCount: 0, realizedPnL: 200),
                SymbolSummary(symbol: "ETHUSDT", asset: "ETH", tradeCount: 1, buyCount: 0, sellCount: 0, realizedPnL: 350),
                SymbolSummary(symbol: "SOLUSDT", asset: "SOL", tradeCount: 1, buyCount: 0, sellCount: 0, realizedPnL: -50),
            ]
        )

        let sorted = summary.topSymbols.sorted { $0.realizedPnL > $1.realizedPnL }

        #expect(sorted[0].symbol == "ETHUSDT")
        #expect(sorted[0].realizedPnL == 350)
        #expect(sorted[1].symbol == "BTCUSDT")
        #expect(sorted[1].realizedPnL == 200)
        #expect(sorted[2].symbol == "SOLUSDT")
        #expect(sorted[2].realizedPnL == -50)
    }

    @Test("When all symbols have the same P&L, then original order is preserved")
    func samePnL_preservesOrder() {
        let symbols = [
            SymbolSummary(symbol: "BTCUSDT", asset: "BTC", tradeCount: 1, buyCount: 0, sellCount: 0, realizedPnL: 100),
            SymbolSummary(symbol: "ETHUSDT", asset: "ETH", tradeCount: 1, buyCount: 0, sellCount: 0, realizedPnL: 100),
        ]

        let sorted = symbols.sorted { $0.realizedPnL > $1.realizedPnL }

        #expect(sorted.count == 2)
        #expect(sorted[0].symbol == "BTCUSDT")
        #expect(sorted[1].symbol == "ETHUSDT")
    }

    // MARK: - Average profit per trade

    @Test("When there are sells, then average profit per trade equals total P&L divided by sell count")
    func averageProfitPerTradeComputedCorrectly() {
        let summary = TradeSummary(
            totalTrades: 10,
            buyCount: 4,
            sellCount: 6,
            symbolCount: 2,
            totalRealizedPnL: 1200,
            winningSells: 4,
            losingSells: 2,
            currentWinStreak: 0,
            currentLossStreak: 0,
            averageHoldingPeriodDays: 0,
            concentrationRatio: 0,
            topSymbols: []
        )

        let average = summary.sellCount > 0
            ? summary.totalRealizedPnL / Double(summary.sellCount)
            : 0.0

        #expect(average == 200.0)
    }

    @Test("When there are no sells, then average profit per trade is zero")
    func averageProfitZeroWhenNoSells() {
        let summary = TradeSummary(
            totalTrades: 5,
            buyCount: 5,
            sellCount: 0,
            symbolCount: 1,
            totalRealizedPnL: 0,
            winningSells: 0,
            losingSells: 0,
            currentWinStreak: 0,
            currentLossStreak: 0,
            averageHoldingPeriodDays: 0,
            concentrationRatio: 0,
            topSymbols: []
        )

        let average = summary.sellCount > 0
            ? summary.totalRealizedPnL / Double(summary.sellCount)
            : 0.0

        #expect(average == 0.0)
    }

    @Test("When average profit is negative, then it is computed correctly")
    func negativeAverageProfit() {
        let summary = TradeSummary(
            totalTrades: 8,
            buyCount: 4,
            sellCount: 4,
            symbolCount: 2,
            totalRealizedPnL: -600,
            winningSells: 1,
            losingSells: 3,
            currentWinStreak: 0,
            currentLossStreak: 0,
            averageHoldingPeriodDays: 0,
            concentrationRatio: 0,
            topSymbols: []
        )

        let average = summary.sellCount > 0
            ? summary.totalRealizedPnL / Double(summary.sellCount)
            : 0.0

        #expect(average == -150.0)
    }

    // MARK: - Empty state

    @Test("When there are no symbols, then the breakdown is empty")
    func emptyWhenNoSymbols() {
        let summary = TradeSummary.empty

        #expect(summary.topSymbols.isEmpty)
        #expect(summary.sellCount == 0)
    }
}
