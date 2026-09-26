//
//  FIFOCalculatorBugFixTests.swift
//  EasyCryptoTests
//
//  ADV-CORE-SERVICES-012: Tests for FIFO commission handling bugs.
//  These tests document the bugs and will fail until the fixes are applied.

import Foundation
import Testing
@testable import EasyCrypto

@Suite("Given a FIFO calculator with commission handling bugs")
struct FIFOCommissionBugFixTests {

    // MARK: - BNB Buy Commission Should Not Inflate Cost Basis

    @Test("When buy commission is in BNB (non-base, non-USDT), then cost basis is NOT inflated")
    func bnbBuyCommissionDoesNotInflateCostBasis() {
        // Bug: line 122 condition `commissionAsset == "USDT" || commission > 0`
        // causes BNB commissions to be treated as USDT, inflating lot price.
        // Buy 1.0 BTC @ 50000 USDT, pay 0.01 BNB commission.
        // BNB price is unknown to FIFO engine, so commission should be IGNORED.
        // Expected: lotPrice = 50000, totalInvested = 50000
        // Bug behavior: lotPrice = (50000 + 0.01) / 1.0 = 50000.01
        let trades = [
            makeTrade(
                price: 50000, quantity: 1.0, isBuyer: true,
                commission: 0.01, commissionAsset: "BNB", asset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].remainingQuantity == 1.0)
        #expect(result.remainingLots[0].price == 50000,
               "BNB commission should not inflate lot price, got \(result.remainingLots[0].price)")
        #expect(result.totalInvestedUSDT == 50000,
               "BNB commission should not add to total invested, got \(result.totalInvestedUSDT)")
    }

    @Test("When buy commission is in USDT, then cost basis IS inflated correctly")
    func usdtBuyCommissionInflatesCostBasis() {
        // Buy 1.0 BTC @ 50000 USDT, pay 50 USDT commission.
        // Expected: lotPrice = (50000 + 50) / 1.0 = 50050
        let trades = [
            makeTrade(
                price: 50000, quantity: 1.0, isBuyer: true,
                commission: 50, commissionAsset: "USDT", asset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        #expect(result.remainingLots[0].price == 50050)
        #expect(result.totalInvestedUSDT == 50050)
    }

    @Test("When buy commission is in base asset, then lot price is inflated correctly")
    func baseAssetBuyCommissionInflatesLotPrice() {
        // Buy 1.0 BTC @ 50000, pay 0.001 BTC commission.
        // Expected: lotPrice = 50000 * 1.0 / 0.999 = 50050.05
        let trades = [
            makeTrade(
                price: 50000, quantity: 1.0, isBuyer: true,
                commission: 0.001, commissionAsset: "BTC", asset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        let expectedPrice = 50000.0 * 1.0 / 0.999
        #expect(abs(result.remainingLots[0].price - expectedPrice) < 0.01)
        #expect(result.totalInvestedUSDT == 50000)
    }

    // MARK: - Base-Asset Sell Commission Bugs

    @Test("When sell commission is in base asset, then P&L reflects full commission cost")
    func baseAssetSellCommissionFullyDeducted() {
        // Buy 1.0005 BTC @ 50000 (commission 0.0005 BTC → net 1.000 BTC held)
        // Wait, let me redo this correctly:
        // Buy 1.0 BTC @ 50000, sell 0.999 BTC @ 55000 with 0.0005 BTC commission.
        // sellQty = 0.999 + 0.0005 = 0.9995
        // consumed = min(1.0, 0.9995) = 0.9995
        // soldPortion = min(0.9995, 0.999) = 0.999
        // feePortion = 0.9995 - 0.999 = 0.0005
        // P&L += 0.999 * (55000 - 50000) = 49950
        // P&L -= 0.0005 * 50000 = 25
        // Net P&L = 49925
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(
                price: 55000, quantity: 0.999, isBuyer: false,
                commission: 0.0005, commissionAsset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(abs(result.remainingLots[0].remainingQuantity - 0.0005) < 1e-10)
        let expectedPnL = 0.999 * (55000 - 50000) - 0.0005 * 50000
        #expect(abs(result.realizedPnL - expectedPnL) < 0.01,
               "Expected P&L \(expectedPnL), got \(result.realizedPnL)")
    }

    @Test("When sell commission in base asset exceeds lot quantity, then excess is deducted from proceeds")
    func baseAssetSellCommissionExceedsLotDeductedFromProceeds() {
        // Buy 1.0 BTC @ 50000.
        // Sell 0.5 BTC @ 55000 with 0.6 BTC commission.
        // sellQty = 0.5 + 0.6 = 1.1 (total to consume)
        // consumedTotal = 1.0 (all of lot)
        // soldPortion = min(1.0, 0.5) = 0.5
        // feePortion = 1.0 - 0.5 = 0.5
        // excess = 1.1 - 1.0 = 0.1 (commission that couldn't be satisfied by lot)
        // P&L += 0.5 * (55000 - 50000) = 2500
        // P&L -= 0.5 * 50000 = 25000
        // P&L -= excess * lastLotPrice = 0.1 * 50000 = 5000
        // Net P&L = 2500 - 25000 - 5000 = -22500
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(
                price: 55000, quantity: 0.5, isBuyer: false,
                commission: 0.6, commissionAsset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        let expectedPnL = 0.5 * (55000 - 50000) - 0.5 * 50000 - 0.1 * 50000
        #expect(abs(result.realizedPnL - expectedPnL) < 0.01,
               "Expected P&L \(expectedPnL), got \(result.realizedPnL)")
    }
}

// MARK: - Helpers (duplicated from FIFOCalculatorTests.swift for test independence)

private func makeTrade(
    price: Double,
    quantity: Double,
    isBuyer: Bool,
    commission: Double = 0,
    commissionAsset: String = "BNB",
    asset: String = "BTC"
) -> FIFOTrade {
    FIFOTrade(
        price: price,
        quantity: quantity,
        commission: commission,
        commissionAsset: commissionAsset,
        asset: asset,
        isBuyer: isBuyer
    )
}
