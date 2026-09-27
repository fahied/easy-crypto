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
        // Buy 1.0 BTC @ 50000 → lot holds 1.0 BTC @ 50000 (fee already deducted on buy).
        // Sell 0.999 BTC @ 55000 with 0.0005 BTC commission.
        // Only 0.999 is consumed from lot; fee valued at market price (55000).
        // P&L = 0.999 * (55000 - 50000) - 0.0005 * 55000 = 49950 - 27.50 = 49922.50
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(
                price: 55000, quantity: 0.999, isBuyer: false,
                commission: 0.0005, commissionAsset: "BTC"
            ),
        ]
        let result = FIFOCalculator.live.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(abs(result.remainingLots[0].remainingQuantity - 0.001) < 1e-10,
               "Remaining lot should be 0.001 (1.0 - 0.999), got \(result.remainingLots[0].remainingQuantity)")
        let expectedPnL = 0.999 * (55000 - 50000) - 0.0005 * 55000
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
