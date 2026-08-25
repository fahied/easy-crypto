//
//  PortfolioState.swift
//  EasyCrypto
//

import Foundation

struct PortfolioState: ViewState {
    var summary: PortfolioSummary = .empty
    var isLoading: Bool = false
    var error: String?
    var lastRefreshDate: Date?
    var sortBy: SortCriteria = .value

    /// Navigation destination: invested-assets detail sheet/push.
    var investedAssetsDestination: InvestedAssetsDestination?
}

struct InvestedAssetsDestination: Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    let assets: [InvestedAssetRow]
    let totalInvested: Double
    let totalCurrentValue: Double
}

struct InvestedAssetRow: Equatable, Identifiable, Sendable {
    let id: String
    let asset: String
    let tradingMode: TradingMode
    let amountInvestedUSDT: Double
    let currentValueUSDT: Double

    init(asset: String, tradingMode: TradingMode, amountInvestedUSDT: Double, currentValueUSDT: Double) {
        self.id = asset + tradingMode.rawValue
        self.asset = asset
        self.tradingMode = tradingMode
        self.amountInvestedUSDT = amountInvestedUSDT
        self.currentValueUSDT = currentValueUSDT
    }
}
