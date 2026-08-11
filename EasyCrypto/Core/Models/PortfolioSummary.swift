//
//  PortfolioSummary.swift
//  EasyCrypto
//

import Foundation

nonisolated struct PortfolioSummary: Equatable, Sendable {
    let totalInvestedUSDT: Double
    let totalCurrentValueUSDT: Double
    let totalUnrealizedPnL: Double
    let totalUnrealizedPnLPercent: Double
    let totalRealizedPnL: Double
    let holdingsCount: Int

    var totalPnL: Double {
        totalRealizedPnL + totalUnrealizedPnL
    }

        var isEmpty: Bool {
            holdingsCount == 0
        }
    
    var totalPnLPercent: Double {
        totalInvestedUSDT > 0 ? (totalPnL / totalInvestedUSDT) * 100.0 : 0.0
    }

    static let empty = PortfolioSummary(
        totalInvestedUSDT: 0,
        totalCurrentValueUSDT: 0,
        totalUnrealizedPnL: 0,
        totalUnrealizedPnLPercent: 0,
        totalRealizedPnL: 0,
        holdingsCount: 0
    )

    init(
        totalInvestedUSDT: Double,
        totalCurrentValueUSDT: Double,
        totalUnrealizedPnL: Double,
        totalUnrealizedPnLPercent: Double,
        totalRealizedPnL: Double,
        holdingsCount: Int
    ) {
        self.totalInvestedUSDT = totalInvestedUSDT
        self.totalCurrentValueUSDT = totalCurrentValueUSDT
        self.totalUnrealizedPnL = totalUnrealizedPnL
        self.totalUnrealizedPnLPercent = totalUnrealizedPnLPercent
        self.totalRealizedPnL = totalRealizedPnL
        self.holdingsCount = holdingsCount
    }

    init(from holdings: [Holding]) {
        self.init(from: holdings, totalRealizedPnL: nil)
    }

    init(from holdings: [Holding], totalRealizedPnL: Double?) {
        let invested = holdings.reduce(0.0) { $0 + $1.totalInvestedUSDT }
        let currentValue = holdings.reduce(0.0) { $0 + $1.currentValueUSDT }
        let unrealizedPnL = holdings.reduce(0.0) { $0 + $1.unrealizedPnL }
        let realizedPnL = totalRealizedPnL ?? holdings.reduce(0.0) { $0 + $1.realizedPnL }
        let percent = invested > 0 ? (unrealizedPnL / invested) * 100.0 : 0.0

        self.totalInvestedUSDT = invested
        self.totalCurrentValueUSDT = currentValue
        self.totalUnrealizedPnL = unrealizedPnL
        self.totalUnrealizedPnLPercent = percent
        self.totalRealizedPnL = realizedPnL
        self.holdingsCount = holdings.count
    }
}
