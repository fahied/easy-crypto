//
//  Holding.swift
//  EasyCrypto
//

import Foundation

nonisolated struct Holding: Equatable, Sendable, Identifiable, Hashable {
    var id: String { asset + tradingMode.rawValue }

    let asset: String
    let totalQuantity: Double
    let weightedAvgBuyPrice: Double
    let totalInvestedUSDT: Double
    let currentPrice: Double
    let currentValueUSDT: Double
    let unrealizedPnL: Double
    let unrealizedPnLPercent: Double
    let realizedPnL: Double
    let tradingMode: TradingMode

    /// Available (free) balance for trading.
    let availableBalance: Double
    /// Locked (in-order) balance.
    let lockedBalance: Double

    // MARK: - Margin Fields

    /// Quantity borrowed on margin (nil for spot).
    let borrowedQuantity: Double?
    /// P&L after borrowing fee deduction (nil for spot).
    let marginAdjustedPnL: Double?
    /// Estimated liquidation price — populated for isolated-margin (nil for spot/cross).
    let liquidationPrice: Double?

    /// Cumulative borrowing fees paid on this position (margin only, 0 for spot).
    let borrowingFeeUSDT: Double

    init(
        asset: String,
        totalQuantity: Double,
        weightedAvgBuyPrice: Double,
        totalInvestedUSDT: Double,
        currentPrice: Double,
        currentValueUSDT: Double,
        unrealizedPnL: Double,
        unrealizedPnLPercent: Double,
        realizedPnL: Double,
        tradingMode: TradingMode = .spot,
        availableBalance: Double? = nil,
        lockedBalance: Double? = nil,
        borrowedQuantity: Double? = nil,
        marginAdjustedPnL: Double? = nil,
        liquidationPrice: Double? = nil,
        borrowingFeeUSDT: Double = 0
    ) {
        self.asset = asset
        self.totalQuantity = totalQuantity
        self.weightedAvgBuyPrice = weightedAvgBuyPrice
        self.totalInvestedUSDT = totalInvestedUSDT
        self.currentPrice = currentPrice
        self.currentValueUSDT = currentValueUSDT
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPercent = unrealizedPnLPercent
        self.realizedPnL = realizedPnL
        self.tradingMode = tradingMode
        self.availableBalance = availableBalance ?? totalQuantity
        self.lockedBalance = lockedBalance ?? 0
        self.borrowedQuantity = borrowedQuantity
        self.marginAdjustedPnL = marginAdjustedPnL
        self.liquidationPrice = liquidationPrice
        self.borrowingFeeUSDT = borrowingFeeUSDT
    }
}
