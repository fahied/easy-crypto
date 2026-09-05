//
//  HoldingFactoryTests.swift
//  EasyCryptoTests
//
//  Invested = FIFO survivor lots only (totalInvestedUSDT).
//  Quantity = FIFO remaining quantity (not wallet balance).
//  avgBuyPrice = invested / fifoQuantity — used by views for P&L color + display.
//  P&L = (fifoQuantity × currentPrice) − invested.
//
import Foundation
import Testing
import SwiftData

@testable import EasyCrypto

// MARK: - Helpers

private func makeFIFOResult(
    totalRemainingQuantity: Double = 0,
    totalInvestedUSDT: Double = 0,
    realizedPnL: Double = 0
) -> FIFOResult {
    FIFOResult(
        remainingLots: [],
        totalRemainingQuantity: totalRemainingQuantity,
        weightedAvgBuyPrice: 0,
        totalInvestedUSDT: totalInvestedUSDT,
        realizedPnL: realizedPnL,
        totalBoughtUSDT: 0,
        totalBoughtQuantity: 0
    )
}

// MARK: - HoldingFactory

@Suite("Given HoldingFactory")
struct HoldingFactoryTests {

    @Test("When a single buy has no sell, invested equals price × qty")
    func singleBuyInvested() {
        let qty: Double = 0.25587387
        let buyPrice: Double = 78084.01
        let invested = buyPrice * qty
        let fifo = makeFIFOResult(
            totalRemainingQuantity: qty,
            totalInvestedUSDT: invested
        )
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: qty,
            currentPrice: 80000,
            fifo: fifo
        )

        #expect(holding.totalQuantity == qty)
        #expect(holding.totalInvestedUSDT == invested)
        #expect(abs(holding.weightedAvgBuyPrice - buyPrice) < 0.001)
        let expectedPnL = qty * 80000 - invested
        #expect(abs(holding.unrealizedPnL - expectedPnL) < 0.01)
    }

    @Test("When partial sells happened, invested reflects only surviving lots")
    func partialSellInvestedFromFIFO() {
        let remainingQty: Double = 1.5
        let invested: Double = 115_000
        let expectedAvg = invested / remainingQty
        let fifo = makeFIFOResult(
            totalRemainingQuantity: remainingQty,
            totalInvestedUSDT: invested
        )
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: remainingQty,
            currentPrice: 85000,
            fifo: fifo
        )

        #expect(holding.totalQuantity == remainingQty)
        #expect(holding.totalInvestedUSDT == invested)
        #expect(abs(holding.weightedAvgBuyPrice - expectedAvg) < 0.01)
        let expectedPnL = remainingQty * 85000 - invested
        #expect(abs(holding.unrealizedPnL - expectedPnL) < 0.01)
    }

    @Test("When wallet qty exceeds FIFO qty, avgBuyPrice uses FIFO not wallet")
    func walletQuantityExceedsFIFOQuantity() {
        let walletQty: Double = 0.25587387
        let fifoQty: Double = 0.246
        let invested: Double = 19207.02227151035

        let fifo = makeFIFOResult(
            totalRemainingQuantity: fifoQty,
            totalInvestedUSDT: invested
        )
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: walletQty,
            currentPrice: 80000,
            fifo: fifo
        )

        #expect(holding.totalQuantity == walletQty)
        #expect(holding.totalInvestedUSDT == invested)
        #expect(abs(holding.weightedAvgBuyPrice - (invested / fifoQty)) < 0.001)
        #expect(abs(holding.weightedAvgBuyPrice - (invested / walletQty)) > 5)
        let expectedPnL = fifoQty * 80000 - invested
        #expect(abs(holding.unrealizedPnL - expectedPnL) < 0.01)
    }

    @Test("When quantity is zero, invested is zero and P&L is zero")
    func zeroQuantityZeroCost() {
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: 0,
            currentPrice: 80000,
            fifo: makeFIFOResult(totalInvestedUSDT: 0)
        )

        #expect(holding.totalQuantity == 0)
        #expect(holding.totalInvestedUSDT == 0)
        #expect(holding.weightedAvgBuyPrice == 0)
        #expect(holding.unrealizedPnL == 0)
        #expect(holding.unrealizedPnLPercent == 0)
    }

    @Test("When fifo is empty, unrealized P&L is zero")
    func emptyFIFONoPnL() {
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: 0.5,
            currentPrice: 80000,
            fifo: .empty
        )

        #expect(holding.totalQuantity == 0)
        #expect(holding.totalInvestedUSDT == 0)
        #expect(holding.weightedAvgBuyPrice == 0)
        #expect(holding.unrealizedPnL == 0)
        #expect(holding.unrealizedPnLPercent == 0)
    }

    @Test("When invested > 0, P&L percent is (currentValue - invested) / invested")
    func pnlPercentFormula() {
        let qty: Double = 1
        let invested: Double = 50_000
        let fifo = makeFIFOResult(
            totalRemainingQuantity: qty,
            totalInvestedUSDT: invested
        )
        let holding = HoldingFactory.make(
            asset: "BTC",
            quantity: qty,
            currentPrice: 60000,
            fifo: fifo
        )

        let expectedCurrentValue = qty * 60000
        let expectedPnL = expectedCurrentValue - invested
        let expectedPnLPercent = (expectedPnL / invested) * 100
        #expect(abs(holding.unrealizedPnL - expectedPnL) < 0.01)
        #expect(abs(holding.unrealizedPnLPercent - expectedPnLPercent) < 0.01)
    }
}
