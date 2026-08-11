//
//  PortfolioSummary.swift
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

    // MARK: - Per-Mode Breakdown

    let spot: ModeSummary
    let crossMargin: ModeSummary
    let isolatedMargin: ModeSummary

    struct ModeSummary: Equatable, Sendable {
        let investedUSDT: Double
        let currentValueUSDT: Double
        let unrealizedPnL: Double
        let unrealizedPnLPercent: Double
        let realizedPnL: Double
        let holdingsCount: Int

        var isActive: Bool { holdingsCount > 0 }
    }

    // MARK: - Initializers

    static let empty = PortfolioSummary(
        totalInvestedUSDT: 0,
        totalCurrentValueUSDT: 0,
        totalUnrealizedPnL: 0,
        totalUnrealizedPnLPercent: 0,
        totalRealizedPnL: 0,
        holdingsCount: 0,
        spot: .empty,
        crossMargin: .empty,
        isolatedMargin: .empty
    )

    init(
        totalInvestedUSDT: Double,
        totalCurrentValueUSDT: Double,
        totalUnrealizedPnL: Double,
        totalUnrealizedPnLPercent: Double,
        totalRealizedPnL: Double,
        holdingsCount: Int,
        spot: ModeSummary,
        crossMargin: ModeSummary,
        isolatedMargin: ModeSummary
    ) {
        self.totalInvestedUSDT = totalInvestedUSDT
        self.totalCurrentValueUSDT = totalCurrentValueUSDT
        self.totalUnrealizedPnL = totalUnrealizedPnL
        self.totalUnrealizedPnLPercent = totalUnrealizedPnLPercent
        self.totalRealizedPnL = totalRealizedPnL
        self.holdingsCount = holdingsCount
        self.spot = spot
        self.crossMargin = crossMargin
        self.isolatedMargin = isolatedMargin
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
        self.spot = .empty
        self.crossMargin = .empty
        self.isolatedMargin = .empty
    }

    init(from mode: ModeSummary) {
        self.totalInvestedUSDT = mode.investedUSDT
        self.totalCurrentValueUSDT = mode.currentValueUSDT
        self.totalUnrealizedPnL = mode.unrealizedPnL
        self.totalUnrealizedPnLPercent = mode.unrealizedPnLPercent
        self.totalRealizedPnL = mode.realizedPnL
        self.holdingsCount = mode.holdingsCount
        self.spot = .empty
        self.crossMargin = .empty
        self.isolatedMargin = .empty
    }
}

extension PortfolioSummary.ModeSummary {
    static let empty = PortfolioSummary.ModeSummary(
        investedUSDT: 0,
        currentValueUSDT: 0,
        unrealizedPnL: 0,
        unrealizedPnLPercent: 0,
        realizedPnL: 0,
        holdingsCount: 0
    )
}
