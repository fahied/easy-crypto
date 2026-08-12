//
//  Holding.swift
//  EasyCrypto
//

import Foundation

nonisolated struct Holding: Equatable, Sendable, Identifiable, Hashable {
    var id: String { asset }

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

    // MARK: - Margin Fields

    /// Quantity borrowed on margin (nil for spot).
    let borrowedQuantity: Double?
    /// P&L after borrowing fee deduction (nil for spot).
    let marginAdjustedPnL: Double?
    /// Estimated liquidation price — populated for isolated-margin (nil for spot/cross).
    let liquidationPrice: Double?

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
        borrowedQuantity: Double? = nil,
        marginAdjustedPnL: Double? = nil,
        liquidationPrice: Double? = nil
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
        self.borrowedQuantity = borrowedQuantity
        self.marginAdjustedPnL = marginAdjustedPnL
        self.liquidationPrice = liquidationPrice
    }
}
