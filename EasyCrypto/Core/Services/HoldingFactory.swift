//
//  HoldingFactory.swift
//  EasyCrypto
//

import Foundation

/// Builds a `Holding` using the authoritative wallet `quantity` for display.
///
/// Invested is the raw sum of all buy order values (`price × quantity`) from
/// trade history — no FIFO, no averaging, unaffected by sells. Current value
/// is the wallet balance times the live ticker. P&L is the simple difference.
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
        let invested = fifo.totalInvestedUSDT
        let fifoQuantity = fifo.totalRemainingQuantity
        let avgBuyPrice = fifoQuantity > 0 ? invested / fifoQuantity : 0
        let currentValue = fifoQuantity * currentPrice
        let unrealizedPnL = invested > 0 ? currentValue - invested : 0
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
            tradingMode: tradingMode,
            borrowedQuantity: borrowedQuantity,
            marginAdjustedPnL: marginAdjustedPnL,
            liquidationPrice: liquidationPrice
        )
    }
}
