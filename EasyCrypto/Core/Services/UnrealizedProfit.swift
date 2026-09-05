//
//  UnrealizedProfit.swift
//  EasyCrypto
//

import Foundation

/// Shared helper for computing per-asset unrealized USDT profit from chronological
/// trades and a current price. Used by background price-alert evaluation.
nonisolated enum UnrealizedProfit {
    /// Unrealized USDT profit for one asset. Uses `weightedAvgBuyPrice` so
    /// invested reflects the cost basis of remaining lots only.
    /// Returns 0 when no quantity remains.
    static func compute(
        trades: [FIFOTrade],
        currentPrice: Double,
        using calculator: FIFOCalculator
    ) -> Double {
        let result = calculator.calculate(trades)
        let invested = result.totalInvestedUSDT
        let qty = result.totalRemainingQuantity
        guard qty > 0 else { return 0 }
        return qty * currentPrice - invested
    }
}
