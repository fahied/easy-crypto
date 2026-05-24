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

// MARK: - Calculator (struct-with-closures pattern)

nonisolated struct FIFOCalculator: Sendable {
    var calculate: @Sendable (_ trades: [FIFOTrade]) -> FIFOResult
}

// MARK: - Live Implementation

extension FIFOCalculator {
    static let live = FIFOCalculator(
        calculate: { trades in
            guard !trades.isEmpty else { return .empty }

            var lots: [BuyLot] = []
            var realizedPnL: Double = 0

            for trade in trades {
                if trade.isBuyer {
                    var qty = trade.quantity
                    // Commission in the base asset reduces received quantity
                    if trade.commissionAsset == trade.asset {
                        qty -= trade.commission
                    }
                    lots.append(BuyLot(price: trade.price, remainingQuantity: qty))
                } else {
                    // Sell — consume lots in FIFO order
                    var sellQty = trade.quantity

                    while sellQty > 0 && !lots.isEmpty {
                        let consumed = min(lots[0].remainingQuantity, sellQty)
                        realizedPnL += consumed * (trade.price - lots[0].price)
                        lots[0].remainingQuantity -= consumed
                        sellQty -= consumed

                        if lots[0].remainingQuantity <= 0 {
                            lots.removeFirst()
                        }
                    }

                    // Commission in USDT reduces realized proceeds
                    if trade.commissionAsset == "USDT" {
                        realizedPnL -= trade.commission
                    }
                }
            }

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
    )
}

// MARK: - Preview & Noop

extension FIFOCalculator {
    static let preview = live

    static let noop = FIFOCalculator(
        calculate: { _ in .empty }
    )
}
