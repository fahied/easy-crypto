//
//  MarginFIFOCalculatorTests.swift
//  EasyCryptoTests
//
//  ADV-CORE-SERVICES-008: Tests for margin-aware FIFO calculator.

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given a margin-aware FIFOCalculator")
struct MarginFIFOCalculatorTests {

    // MARK: - calculateMargin

    @Test("When trades include sells and fees, then borrowing fees are subtracted from realized P&L")
    func marginSubtractsBorrowingFees() async throws {
        // Buy 1 BTC @ 50k, sell 0.5 BTC @ 55k = 2500 profit before fees
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 1.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 0.5, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
        ]
        let fees: [String: Double] = ["BTC": 0.05]

        let result = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(result.isMarginPosition == true)
        #expect(result.totalBorrowingFees == 0.05)
        #expect(result.marginAdjustedRealizedPnL == result.realizedPnL - 0.05)
    }

    @Test("When borrowing fees span multiple assets, then they are summed")
    func marginSumsMultiAssetFees() async throws {
        // Buy BTC @ 50k, sell 0.5 BTC @ 55k
        // Buy ETH @ 3000, sell 2 ETH @ 3500
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 1.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 0.5, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
            .init(price: 3000, quantity: 5.0, commission: 0.01, commissionAsset: "ETH",
                  asset: "ETH", isBuyer: true),
            .init(price: 3500, quantity: 2.0, commission: 0.01, commissionAsset: "USDT",
                  asset: "ETH", isBuyer: false),
        ]
        let fees: [String: Double] = ["BTC": 0.05, "ETH": 0.10]

        let result = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(result.isMarginPosition == true)
        #expect(result.totalBorrowingFees == 0.15)
        #expect(result.marginAdjustedRealizedPnL == result.realizedPnL - 0.15)
    }

    @Test("When zero fees are provided, then margin P&L matches spot P&L exactly")
    func zeroFeesMatchSpot() async throws {
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 1.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 0.5, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
        ]
        let fees: [String: Double] = [:]

        let spotResult = FIFOCalculator.live.calculate(trades)
        let marginResult = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(marginResult.isMarginPosition == true)
        #expect(marginResult.realizedPnL == spotResult.realizedPnL)
        #expect(marginResult.totalBorrowingFees == 0)
        #expect(marginResult.marginAdjustedRealizedPnL == spotResult.realizedPnL)
    }

    @Test("When no trades are provided, then it returns empty regardless of fees")
    func marginEmptyTrades() async throws {
        let fees: [String: Double] = ["BTC": 1.0]

        let result = FIFOCalculator.live.calculateMargin([], fees)

        #expect(result == .empty)
        #expect(result.isMarginPosition == false)
    }

    @Test("When only buy trades exist, then isMarginPosition is false (no P&L to adjust)")
    func marginBuyOnlyIsNotMarginPosition() async throws {
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 0.1, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
        ]
        let fees: [String: Double] = ["BTC": 0.05]

        let result = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(result.realizedPnL == 0)
        #expect(result.totalBorrowingFees == 0.05)
        #expect(result.marginAdjustedRealizedPnL == -0.05)
        #expect(result.isMarginPosition == false)
    }

    @Test("marginAdjustedRealizedPnL equals realizedPnL minus totalBorrowingFees")
    func marginAdjustedPnLFormula() async throws {
        let trades: [FIFOTrade] = [
            .init(price: 100, quantity: 10, commission: 0.01, commissionAsset: "ETH",
                  asset: "ETH", isBuyer: true),
            .init(price: 120, quantity: 5, commission: 0.005, commissionAsset: "ETH",
                  asset: "ETH", isBuyer: false),
        ]
        let fees: [String: Double] = ["ETH": 0.75]

        let result = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(result.marginAdjustedRealizedPnL == result.realizedPnL - result.totalBorrowingFees)
    }

    @Test("When trades include buys and sells, then remainingLots and quantities match calculate")
    func marginRemainingLotsMatchSpot() async throws {
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 2.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 1.0, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
        ]
        let fees: [String: Double] = ["BTC": 0.05]

        let spotResult = FIFOCalculator.live.calculate(trades)
        let marginResult = FIFOCalculator.live.calculateMargin(trades, fees)

        #expect(marginResult.totalRemainingQuantity == spotResult.totalRemainingQuantity)
        #expect(marginResult.weightedAvgBuyPrice == spotResult.weightedAvgBuyPrice)
        #expect(marginResult.totalInvestedUSDT == spotResult.totalInvestedUSDT)
        #expect(marginResult.fifoResult.realizedPnL == spotResult.realizedPnL)
    }

    // MARK: - saleBreakdowns with borrowingFeePerUnit

    @Test("When borrowingFeePerUnit is provided, then it deducts fees from each breakdown")
    func saleBreakdownsWithBorrowingFee() async throws {
        // Buy 2 BTC @ 50k, sell 1 BTC @ 55k
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 2.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 1.0, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
        ]
        let feePerUnit = 0.01 // 0.01 per BTC sold = 0.01 total

        let breakdowns = FIFOCalculator.live.saleBreakdownsWithBorrowingFee(trades, feePerUnit)

        let sellBreakdown = breakdowns[1]!
        // Without fee: (55000 - 50000) * 1 = 5000
        // With fee: 5000 - 0.01 = 4999.99
        #expect(abs(sellBreakdown.realizedPnL - 4999.99) < 1e-9)
    }

    @Test("When feePerUnit is zero, then saleBreakdownsWithBorrowingFee matches saleBreakdowns")
    func saleBreakdownsZeroFeeMatchesOriginal() async throws {
        let trades: [FIFOTrade] = [
            .init(price: 50000, quantity: 2.0, commission: 0.001, commissionAsset: "BTC",
                  asset: "BTC", isBuyer: true),
            .init(price: 55000, quantity: 1.0, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
            .init(price: 54000, quantity: 0.5, commission: 0.001, commissionAsset: "USDT",
                  asset: "BTC", isBuyer: false),
        ]

        let breakdownsStandard = FIFOCalculator.live.saleBreakdowns(trades)
        let breakdownsWithZeroFee = FIFOCalculator.live.saleBreakdownsWithBorrowingFee(trades, 0)

        #expect(breakdownsStandard.count == breakdownsWithZeroFee.count)
        for (std, zero) in zip(breakdownsStandard, breakdownsWithZeroFee) {
            switch (std, zero) {
            case (nil, nil):
                break
            case let (a?, b?):
                #expect(abs(a.realizedPnL - b.realizedPnL) < 1e-9)
                #expect(abs(a.costBasisPrice - b.costBasisPrice) < 1e-9)
            default:
                Issue.record("Mismatched nil/non-nil breakdowns")
            }
        }
    }
}
