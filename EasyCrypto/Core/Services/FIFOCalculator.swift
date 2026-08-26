//
//  FIFOCalculator.swift
//  EasyCrypto
//

import Foundation

// MARK: - Types

/// A simplified trade input for FIFO calculation.
/// Trades must be passed in chronological order.
nonisolated struct FIFOTrade: Equatable, Sendable {
    let price: Double
    let quantity: Double
    let commission: Double
    let commissionAsset: String
    let asset: String
    let isBuyer: Bool
}

/// A single buy lot in the FIFO queue.
nonisolated struct BuyLot: Equatable, Sendable {
    let price: Double
    var remainingQuantity: Double
}

/// Result of running FIFO calculation on trades for one asset.
nonisolated struct FIFOResult: Equatable, Sendable {
    let remainingLots: [BuyLot]
    let totalRemainingQuantity: Double
    let weightedAvgBuyPrice: Double
    let totalInvestedUSDT: Double
    let realizedPnL: Double

    static let empty = FIFOResult(
        remainingLots: [],
        totalRemainingQuantity: 0,
        weightedAvgBuyPrice: 0,
        totalInvestedUSDT: 0,
        realizedPnL: 0
    )
}

/// Cost-basis breakdown for a single sell trade, derived from the FIFO lots it consumed.
nonisolated struct SaleBreakdown: Equatable, Sendable {
    /// Weighted average buy price of the lots consumed by this sell.
    let costBasisPrice: Double
    /// Original USDT invested in the quantity being sold (`costBasisPrice * quantitySold`).
    let costBasisAmount: Double
    /// Realized profit/loss for this individual sell (net of fees).
    let realizedPnL: Double
    /// Borrowing fee deducted for this sell (0 for spot trades).
    let borrowingFee: Double
}

/// Margin-adjusted FIFO result. Wraps `FIFOResult` and adds borrowing fee
/// deduction and margin position detection.
nonisolated struct MarginFIFOResult: Equatable, Sendable {
    let fifoResult: FIFOResult
    let totalBorrowingFees: Double
    let marginAdjustedRealizedPnL: Double
    let isMarginPosition: Bool

    var remainingLots: [BuyLot] { fifoResult.remainingLots }
    var totalRemainingQuantity: Double { fifoResult.totalRemainingQuantity }
    var weightedAvgBuyPrice: Double { fifoResult.weightedAvgBuyPrice }
    var totalInvestedUSDT: Double { fifoResult.totalInvestedUSDT }
    var realizedPnL: Double { fifoResult.realizedPnL }

    static let empty = MarginFIFOResult(
        fifoResult: .empty,
        totalBorrowingFees: 0,
        marginAdjustedRealizedPnL: 0,
        isMarginPosition: false
    )
}

// MARK: - Shared FIFO Engine

nonisolated func fifoCompute(_ trades: [FIFOTrade]) -> FIFOResult {
    guard !trades.isEmpty else { return .empty }

    let epsilon = 1e-12

    var lots: [BuyLot] = []
    var realizedPnL: Double = 0

    for trade in trades {
        if trade.isBuyer {
            var qty = trade.quantity
            if trade.commissionAsset == trade.asset {
                qty -= trade.commission
            }
            if qty > epsilon {
                // When commission is paid in the base asset, the lot price must be
                // inflated so that `lot.price * lot.remainingQuantity` covers the
                // total USD spent on the buy, including commission.
                let lotPrice: Double
                if trade.commissionAsset == trade.asset {
                    lotPrice = trade.price * trade.quantity / qty
                } else {
                    lotPrice = trade.price
                }
                lots.append(BuyLot(price: lotPrice, remainingQuantity: qty))
            }
        } else {
            var sellQty = trade.quantity
            let feeInBaseAsset = trade.commissionAsset == trade.asset ? trade.commission : 0
            var remainingSaleQuantity = trade.quantity
            sellQty += feeInBaseAsset

            while sellQty > 0 && !lots.isEmpty {
                let consumed = min(lots[0].remainingQuantity, sellQty)
                let soldPortion = min(consumed, remainingSaleQuantity)
                let feePortion = consumed - soldPortion

                realizedPnL += soldPortion * (trade.price - lots[0].price)
                realizedPnL -= feePortion * lots[0].price

                lots[0].remainingQuantity -= consumed
                sellQty -= consumed
                remainingSaleQuantity -= soldPortion

                if lots[0].remainingQuantity <= epsilon {
                    lots.removeFirst()
                }
            }

            if trade.commissionAsset == "USDT" {
                realizedPnL -= trade.commission
            }
        }
    }

    lots.removeAll { $0.remainingQuantity <= epsilon }

    let totalRemainingQty = lots.reduce(0.0) { $0 + $1.remainingQuantity }
    let totalInvested = lots.reduce(0.0) { $0 + $1.price * $1.remainingQuantity }
    let weightedAvg = totalRemainingQty > 0 ? totalInvested / totalRemainingQty : 0

    return FIFOResult(
        remainingLots: lots,
        totalRemainingQuantity: totalRemainingQty,
        weightedAvgBuyPrice: weightedAvg,
        totalInvestedUSDT: totalInvested,
        realizedPnL: realizedPnL
    )
}

private func fifoComputeBreakdowns(
    _ trades: [FIFOTrade],
    _ borrowingFeePerUnit: Double?
) -> [SaleBreakdown?] {
    let epsilon = 1e-12

    var lots: [BuyLot] = []
    var breakdowns: [SaleBreakdown?] = []
    breakdowns.reserveCapacity(trades.count)

    for trade in trades {
        if trade.isBuyer {
            var qty = trade.quantity
            if trade.commissionAsset == trade.asset {
                qty -= trade.commission
            }
            if qty > epsilon {
                let lotPrice: Double
                if trade.commissionAsset == trade.asset {
                    lotPrice = trade.price * trade.quantity / qty
                } else {
                    lotPrice = trade.price
                }
                lots.append(BuyLot(price: lotPrice, remainingQuantity: qty))
            }
            breakdowns.append(nil)
        } else {
            let feeInBaseAsset = trade.commissionAsset == trade.asset ? trade.commission : 0
            var sellQty = trade.quantity + feeInBaseAsset
            var remainingSaleQuantity = trade.quantity

            var saleRealizedPnL: Double = 0
            var soldQuantity: Double = 0
            var costBasisAmount: Double = 0

            while sellQty > 0 && !lots.isEmpty {
                let consumed = min(lots[0].remainingQuantity, sellQty)
                let soldPortion = min(consumed, remainingSaleQuantity)
                let feePortion = consumed - soldPortion

                saleRealizedPnL += soldPortion * (trade.price - lots[0].price)
                saleRealizedPnL -= feePortion * lots[0].price

                soldQuantity += soldPortion
                costBasisAmount += soldPortion * lots[0].price

                lots[0].remainingQuantity -= consumed
                sellQty -= consumed
                remainingSaleQuantity -= soldPortion

                if lots[0].remainingQuantity <= epsilon {
                    lots.removeFirst()
                }
            }

            if trade.commissionAsset == "USDT" {
                saleRealizedPnL -= trade.commission
            }

            let borrowingFee: Double
            if let feePerUnit = borrowingFeePerUnit, feePerUnit != 0 {
                borrowingFee = soldQuantity * feePerUnit
                saleRealizedPnL -= borrowingFee
            } else {
                borrowingFee = 0
            }

            let costBasisPrice = soldQuantity > epsilon ? costBasisAmount / soldQuantity : 0

            breakdowns.append(SaleBreakdown(
                costBasisPrice: costBasisPrice,
                costBasisAmount: costBasisAmount,
                realizedPnL: saleRealizedPnL,
                borrowingFee: borrowingFee
            ))
        }
    }

    return breakdowns
}

// MARK: - Calculator (struct-with-closures pattern)

nonisolated struct FIFOCalculator: Sendable {
    var calculate: @Sendable (_ trades: [FIFOTrade]) -> FIFOResult

    /// Returns a per-trade array parallel to `trades`. Buys map to `nil`; each sell maps
    /// to a `SaleBreakdown` describing the cost basis of the lots it consumed.
    /// Trades must be passed in chronological order.
    var saleBreakdowns: @Sendable (_ trades: [FIFOTrade]) -> [SaleBreakdown?]

    /// Like `saleBreakdowns` but distributes a per-unit borrowing fee across each sold
    /// quantity in the breakdown. Fee is deducted from `realizedPnL` per unit sold.
    var saleBreakdownsWithBorrowingFee: @Sendable (
        _ trades: [FIFOTrade],
        _ borrowingFeePerUnit: Double
    ) -> [SaleBreakdown?]

    /// Margin-aware FIFO calculation. Delegates to the FIFO engine for the lot-consumption
    /// algorithm, then subtracts borrowing fees (keyed by asset) from realized P&L.
    ///
    /// Borrowing fees come from `MarginBalanceService`:
    /// - Cross-margin: `CrossMarginAccountData.perAssetInterest`
    /// - Isolated-margin: `IsolatedMarginBalance.interest`
    ///
    /// FIFO mechanics are identical for spot and margin — only cost attribution differs.
    var calculateMargin: @Sendable (
        _ trades: [FIFOTrade],
        _ borrowingFees: [String: Double]
    ) -> MarginFIFOResult
}

// MARK: - Live Implementation

extension FIFOCalculator {
    static let live = FIFOCalculator(
        calculate: fifoCompute,
        saleBreakdowns: { trades in fifoComputeBreakdowns(trades, nil) },
        saleBreakdownsWithBorrowingFee: { trades, fee in
            fifoComputeBreakdowns(trades, fee)
        },
        calculateMargin: { trades, borrowingFees in
            guard !trades.isEmpty else {
                return .empty
            }

            let hasSells = trades.contains { !$0.isBuyer }

            // Run the standard FIFO calculation — algorithm is identical for spot and margin.
            let fifoResult = fifoCompute(trades)

            // Sum borrowing fees across all assets. Fees come from MarginBalanceService:
            // - Cross-margin: CrossMarginAccountData.perAssetInterest
            // - Isolated-margin: IsolatedMarginBalance.interest
            let totalFees = borrowingFees.values.reduce(0, +)

            // isMarginPosition: true when there are sells (realized P&L to adjust).
            // The `calculateMargin` closure is only called in margin context.
            let isMargin = hasSells

            let marginAdjustedPnL = fifoResult.realizedPnL - totalFees

            return MarginFIFOResult(
                fifoResult: fifoResult,
                totalBorrowingFees: totalFees,
                marginAdjustedRealizedPnL: marginAdjustedPnL,
                isMarginPosition: isMargin
            )
        }
    )
}

extension FIFOCalculator {
    static let preview = live

    static let noop = FIFOCalculator(
        calculate: { _ in .empty },
        saleBreakdowns: { trades in trades.map { _ in nil } },
        saleBreakdownsWithBorrowingFee: { trades, _ in trades.map { _ in nil } },
        calculateMargin: { _, _ in .empty }
    )
}
