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
}
