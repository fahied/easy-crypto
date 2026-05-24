//
//  FIFOCalculatorTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing

@testable import EasyCrypto

// MARK: - Helpers

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

private let calculator = FIFOCalculator.live

// MARK: - Empty Trades

@Suite("Given a FIFO calculator with no trades")
struct FIFOEmptyTests {

    @Test("When calculating with empty array, then returns zero result")
    func emptyReturnsZero() {
        let result = calculator.calculate([])
        #expect(result == .empty)
    }
}

// MARK: - Buy-Only Trades

@Suite("Given a FIFO calculator with buy-only trades")
struct FIFOBuyOnlyTests {

    @Test("When processing a single buy, then creates one lot with full quantity")
    func singleBuyCreatesOneLot() {
        let trades = [makeTrade(price: 50000, quantity: 1.0, isBuyer: true)]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].price == 50000)
        #expect(result.remainingLots[0].remainingQuantity == 1.0)
        #expect(result.totalRemainingQuantity == 1.0)
        #expect(result.weightedAvgBuyPrice == 50000)
        #expect(result.totalInvestedUSDT == 50000)
        #expect(result.realizedPnL == 0)
    }

    @Test("When processing DCA buys at different prices, then creates multiple lots with weighted average")
    func dcaBuysCreateMultipleLots() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 60000, quantity: 1.0, isBuyer: true),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.count == 2)
        #expect(result.totalRemainingQuantity == 2.0)
        #expect(result.totalInvestedUSDT == 110_000)
        #expect(result.weightedAvgBuyPrice == 55000)
        #expect(result.realizedPnL == 0)
    }

    @Test("When processing DCA buys with different quantities, then weighted average reflects quantity weights")
    func dcaWeightedByQuantity() {
        let trades = [
            makeTrade(price: 40000, quantity: 3.0, isBuyer: true),  // 120,000
            makeTrade(price: 60000, quantity: 1.0, isBuyer: true),  // 60,000
        ]
        let result = calculator.calculate(trades)

        #expect(result.totalRemainingQuantity == 4.0)
        #expect(result.totalInvestedUSDT == 180_000)
        #expect(result.weightedAvgBuyPrice == 45000)  // 180000 / 4
    }

    @Test("When buy has commission in base asset, then lot quantity is reduced by commission")
    func buyCommissionInBaseAsset() {
        let trades = [
            makeTrade(
                price: 50000, quantity: 1.0, isBuyer: true,
                commission: 0.001, commissionAsset: "BTC", asset: "BTC"
            ),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].remainingQuantity == 0.999)
        #expect(result.totalRemainingQuantity == 0.999)
    }

    @Test("When buy has commission in BNB, then lot quantity is not reduced")
    func buyCommissionInBNB() {
        let trades = [
            makeTrade(
                price: 50000, quantity: 1.0, isBuyer: true,
                commission: 0.01, commissionAsset: "BNB", asset: "BTC"
            ),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots[0].remainingQuantity == 1.0)
    }
}

// MARK: - Buy Then Full Sell

@Suite("Given a FIFO calculator processing a buy then full sell")
struct FIFOFullSellTests {

    @Test("When selling at higher price, then realized P&L is positive")
    func sellAtProfit() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 60000, quantity: 1.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        #expect(result.totalRemainingQuantity == 0)
        #expect(result.weightedAvgBuyPrice == 0)
        #expect(result.totalInvestedUSDT == 0)
        #expect(result.realizedPnL == 10000)  // (60000 - 50000) * 1.0
    }

    @Test("When selling at lower price, then realized P&L is negative")
    func sellAtLoss() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 40000, quantity: 1.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        #expect(result.realizedPnL == -10000)  // (40000 - 50000) * 1.0
    }

    @Test("When selling at same price, then realized P&L is zero")
    func sellAtBreakeven() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 50000, quantity: 1.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.realizedPnL == 0)
    }
}

// MARK: - Partial Sells

@Suite("Given a FIFO calculator processing partial sells")
struct FIFOPartialSellTests {

    @Test("When partially selling from one lot, then remaining quantity is reduced")
    func partialSellReducesLot() {
        let trades = [
            makeTrade(price: 50000, quantity: 2.0, isBuyer: true),
            makeTrade(price: 60000, quantity: 0.5, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].remainingQuantity == 1.5)
        #expect(result.totalRemainingQuantity == 1.5)
        #expect(result.realizedPnL == 5000)  // (60000 - 50000) * 0.5
        #expect(result.totalInvestedUSDT == 75000)  // 50000 * 1.5
    }

    @Test("When selling exactly the first of two lots, then only second lot remains")
    func sellConsumesFirstLot() {
        let trades = [
            makeTrade(price: 40000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 60000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 55000, quantity: 1.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].price == 60000)
        #expect(result.remainingLots[0].remainingQuantity == 1.0)
        #expect(result.realizedPnL == 15000)  // (55000 - 40000) * 1.0
    }

    @Test("When sell crosses lot boundaries, then consumes from multiple lots FIFO")
    func sellCrossesLotBoundaries() {
        let trades = [
            makeTrade(price: 40000, quantity: 1.0, isBuyer: true),  // lot 1
            makeTrade(price: 60000, quantity: 1.0, isBuyer: true),  // lot 2
            makeTrade(price: 50000, quantity: 1.5, isBuyer: false), // sell 1.5
        ]
        let result = calculator.calculate(trades)

        // Should consume all of lot1 (1.0 @ 40000) + 0.5 of lot2 (0.5 @ 60000)
        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].price == 60000)
        #expect(result.remainingLots[0].remainingQuantity == 0.5)
        // P&L: (50000-40000)*1.0 + (50000-60000)*0.5 = 10000 + (-5000) = 5000
        #expect(result.realizedPnL == 5000)
    }

    @Test("When selling all lots across multiple buys, then no lots remain")
    func sellConsumesAllLots() {
        let trades = [
            makeTrade(price: 40000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 60000, quantity: 2.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        #expect(result.totalRemainingQuantity == 0)
        // P&L: (60000-40000)*1.0 + (60000-50000)*1.0 = 20000 + 10000 = 30000
        #expect(result.realizedPnL == 30000)
    }
}

// MARK: - Commission Handling on Sells

@Suite("Given a FIFO calculator with sell commissions")
struct FIFOSellCommissionTests {

    @Test("When sell commission is in USDT, then realized P&L is reduced by commission")
    func sellCommissionInUSDT() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(
                price: 60000, quantity: 1.0, isBuyer: false,
                commission: 60, commissionAsset: "USDT"
            ),
        ]
        let result = calculator.calculate(trades)

        // Gross P&L: (60000-50000)*1 = 10000, minus 60 commission = 9940
        #expect(result.realizedPnL == 9940)
    }

    @Test("When sell commission is in BNB, then realized P&L is not affected")
    func sellCommissionInBNB() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(
                price: 60000, quantity: 1.0, isBuyer: false,
                commission: 0.01, commissionAsset: "BNB"
            ),
        ]
        let result = calculator.calculate(trades)

        #expect(result.realizedPnL == 10000)  // no commission deduction
    }
}

// MARK: - Mixed Sequences

@Suite("Given a FIFO calculator with mixed buy/sell sequences")
struct FIFOMixedSequenceTests {

    @Test("When alternating buys and sells, then FIFO order is maintained")
    func alternatingBuySell() {
        let trades = [
            makeTrade(price: 40000, quantity: 1.0, isBuyer: true),   // lot1
            makeTrade(price: 50000, quantity: 0.5, isBuyer: false),  // sell from lot1
            makeTrade(price: 60000, quantity: 1.0, isBuyer: true),   // lot2
            makeTrade(price: 55000, quantity: 1.0, isBuyer: false),  // sell 0.5 lot1 + 0.5 lot2
        ]
        let result = calculator.calculate(trades)

        // After trade 1: lots = [40000 x 1.0]
        // After trade 2: lots = [40000 x 0.5], realized = (50000-40000)*0.5 = 5000
        // After trade 3: lots = [40000 x 0.5, 60000 x 1.0]
        // After trade 4: sell 1.0 → consume 0.5 from lot1, 0.5 from lot2
        //   realized += (55000-40000)*0.5 + (55000-60000)*0.5 = 7500 + (-2500) = 5000
        //   total realized = 5000 + 5000 = 10000
        #expect(result.remainingLots.count == 1)
        #expect(result.remainingLots[0].price == 60000)
        #expect(result.remainingLots[0].remainingQuantity == 0.5)
        #expect(result.realizedPnL == 10000)
    }

    @Test("When multiple small sells deplete one lot, then moves to next lot")
    func multipleSmallSells() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: true),
            makeTrade(price: 55000, quantity: 0.25, isBuyer: false),
            makeTrade(price: 60000, quantity: 0.25, isBuyer: false),
            makeTrade(price: 45000, quantity: 0.25, isBuyer: false),
            makeTrade(price: 52000, quantity: 0.25, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        // P&L: (55000-50000)*0.25 + (60000-50000)*0.25 + (45000-50000)*0.25 + (52000-50000)*0.25
        //     = 1250 + 2500 + (-1250) + 500 = 3000
        #expect(result.realizedPnL == 3000)
    }
}

// MARK: - Edge Cases

@Suite("Given a FIFO calculator with edge cases")
struct FIFOEdgeCaseTests {

    @Test("When selling with no buy lots, then sells are ignored gracefully")
    func sellWithNoBuys() {
        let trades = [
            makeTrade(price: 50000, quantity: 1.0, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        #expect(result.realizedPnL == 0)
    }

    @Test("When sell quantity exceeds available lots, then consumes all lots and stops")
    func oversell() {
        let trades = [
            makeTrade(price: 50000, quantity: 0.5, isBuyer: true),
            makeTrade(price: 60000, quantity: 1.0, isBuyer: false),  // sell more than owned
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        // Only 0.5 consumed from lot: (60000-50000)*0.5 = 5000
        #expect(result.realizedPnL == 5000)
    }

    @Test("When very small quantities are involved, then computation remains accurate")
    func smallQuantities() {
        let trades = [
            makeTrade(price: 50000, quantity: 0.00001, isBuyer: true),
            makeTrade(price: 60000, quantity: 0.00001, isBuyer: false),
        ]
        let result = calculator.calculate(trades)

        #expect(result.remainingLots.isEmpty)
        let expectedPnL = 0.00001 * (60000.0 - 50000.0)  // 0.1
        #expect(abs(result.realizedPnL - expectedPnL) < 0.0001)
    }
}

// MARK: - Parameterized Weighted Average

struct WeightedAvgScenario: Sendable, CustomTestStringConvertible {
    let buys: [(price: Double, qty: Double)]
    let expectedAvg: Double
    let label: String

    var testDescription: String { label }
}

@Suite("Given FIFO weighted average scenarios")
struct FIFOWeightedAverageTests {

    static let scenarios: [WeightedAvgScenario] = [
        WeightedAvgScenario(
            buys: [(50000, 1.0)],
            expectedAvg: 50000,
            label: "single buy"
        ),
        WeightedAvgScenario(
            buys: [(50000, 1.0), (60000, 1.0)],
            expectedAvg: 55000,
            label: "equal quantities"
        ),
        WeightedAvgScenario(
            buys: [(40000, 3.0), (60000, 1.0)],
            expectedAvg: 45000,
            label: "3:1 quantity ratio"
        ),
        WeightedAvgScenario(
            buys: [(10000, 2.0), (20000, 2.0), (30000, 2.0)],
            expectedAvg: 20000,
            label: "three equal lots"
        ),
    ]

    @Test("Then weighted average reflects quantity-weighted buy prices",
          arguments: scenarios)
    func weightedAverage(scenario: WeightedAvgScenario) {
        let trades = scenario.buys.map { makeTrade(price: $0.price, quantity: $0.qty, isBuyer: true) }
        let result = calculator.calculate(trades)
        #expect(abs(result.weightedAvgBuyPrice - scenario.expectedAvg) < 0.01)
    }
}
