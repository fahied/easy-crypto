//
//  HoldingFactory.swift
//  EasyCrypto
//

import Foundation

/// Builds a `Holding` using the authoritative wallet `quantity` for display, while
/// deriving cost basis, average buy price, and realized P&L from FIFO over the
/// trade history.
///
/// Unrealized P&L is recomputed against the wallet quantity:
/// `(currentPrice − weightedAvgBuyPrice) × quantity`. When there are no buy lots
/// (e.g. an airdrop/reward with no purchase history, or USDT), cost basis is treated
/// as unavailable: invested and unrealized P&L are 0.
nonisolated enum HoldingFactory {
    static func make(
        asset: String,
        quantity: Double,
        currentPrice: Double,
        fifo: FIFOResult,
        tradingMode: TradingMode = .spot,
        borrowedQuantity: Double? = nil,
        marginAdjustedPnL: Double? = nil,
        liquidationPrice: Double? = nil
    ) -> Holding {
        let avgBuyPrice = fifo.weightedAvgBuyPrice
        let hasCostBasis = avgBuyPrice > 0
        let invested = hasCostBasis ? avgBuyPrice * quantity : 0
        let currentValue = quantity * currentPrice
        let unrealizedPnL = hasCostBasis ? (currentPrice - avgBuyPrice) * quantity : 0
        let unrealizedPnLPercent = invested > 0 ? (unrealizedPnL / invested) * 100 : 0

        return Holding(
            asset: asset,
            totalQuantity: quantity,
            weightedAvgBuyPrice: avgBuyPrice,
            totalInvestedUSDT: invested,
            currentPrice: currentPrice,
            currentValueUSDT: currentValue,
            unrealizedPnL: unrealizedPnL,
            unrealizedPnLPercent: unrealizedPnLPercent,
            realizedPnL: fifo.realizedPnL,
            borrowedQuantity: borrowedQuantity,
            marginAdjustedPnL: marginAdjustedPnL,
            liquidationPrice: liquidationPrice
        )
    }
}
