//
//  HoldingTests.swift
//  EasyCryptoTests
//

import Testing
@testable import EasyCrypto

@Suite("Given a Holding value type")
struct HoldingTests {

    @Test("When created with profit scenario, then unrealized P&L is positive")
    func profitScenario() {
        let holding = Holding(
            asset: "BTC",
            totalQuantity: 1.0,
            weightedAvgBuyPrice: 50000.0,
            totalInvestedUSDT: 50000.0,
            currentPrice: 67000.0,
            currentValueUSDT: 67000.0,
            unrealizedPnL: 17000.0,
            unrealizedPnLPercent: 34.0,
            realizedPnL: 0.0
        )

        #expect(holding.asset == "BTC")
        #expect(holding.totalQuantity == 1.0)
        #expect(holding.weightedAvgBuyPrice == 50000.0)
        #expect(holding.totalInvestedUSDT == 50000.0)
        #expect(holding.currentPrice == 67000.0)
        #expect(holding.currentValueUSDT == 67000.0)
        #expect(holding.unrealizedPnL == 17000.0)
        #expect(holding.unrealizedPnLPercent == 34.0)
        #expect(holding.realizedPnL == 0.0)
    }

    @Test("When created with loss scenario, then unrealized P&L is negative")
    func lossScenario() {
        let holding = Holding(
            asset: "ETH",
            totalQuantity: 10.0,
            weightedAvgBuyPrice: 4000.0,
            totalInvestedUSDT: 40000.0,
            currentPrice: 3000.0,
            currentValueUSDT: 30000.0,
            unrealizedPnL: -10000.0,
            unrealizedPnLPercent: -25.0,
            realizedPnL: 500.0
        )

        #expect(holding.unrealizedPnL < 0)
        #expect(holding.unrealizedPnLPercent < 0)
        #expect(holding.realizedPnL == 500.0)
    }

    @Test("When created with zero quantity, then values are zero")
    func zeroQuantity() {
        let holding = Holding(
            asset: "SOL",
            totalQuantity: 0.0,
            weightedAvgBuyPrice: 0.0,
            totalInvestedUSDT: 0.0,
            currentPrice: 150.0,
            currentValueUSDT: 0.0,
            unrealizedPnL: 0.0,
            unrealizedPnLPercent: 0.0,
            realizedPnL: 1000.0
        )

        #expect(holding.totalQuantity == 0.0)
        #expect(holding.currentValueUSDT == 0.0)
        #expect(holding.realizedPnL == 1000.0)
    }

    @Test("When two holdings have same data, then they are equal",
          .enabled(if: true))
    func equatable() {
        let a = Holding(
            asset: "BTC", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
            totalInvestedUSDT: 50000, currentPrice: 60000, currentValueUSDT: 60000,
            unrealizedPnL: 10000, unrealizedPnLPercent: 20, realizedPnL: 0
        )
        let b = Holding(
            asset: "BTC", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
            totalInvestedUSDT: 50000, currentPrice: 60000, currentValueUSDT: 60000,
            unrealizedPnL: 10000, unrealizedPnLPercent: 20, realizedPnL: 0
        )
        #expect(a == b)
    }

    @Test("When holdings differ, then they are not equal")
    func notEquatable() {
        let a = Holding(
            asset: "BTC", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
            totalInvestedUSDT: 50000, currentPrice: 60000, currentValueUSDT: 60000,
            unrealizedPnL: 10000, unrealizedPnLPercent: 20, realizedPnL: 0
        )
        let b = Holding(
            asset: "ETH", totalQuantity: 1.0, weightedAvgBuyPrice: 50000,
            totalInvestedUSDT: 50000, currentPrice: 60000, currentValueUSDT: 60000,
            unrealizedPnL: 10000, unrealizedPnLPercent: 20, realizedPnL: 0
        )
        #expect(a != b)
    }
}
