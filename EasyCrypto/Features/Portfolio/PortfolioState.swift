//
//  PortfolioState.swift
//  EasyCrypto
//

import Foundation

struct SelectedAssetDetail: Equatable, Sendable {
    let asset: String
    let tradingMode: TradingMode
}

struct PortfolioState: ViewState {
    var summary: PortfolioSummary = .empty
    var isLoading: Bool = false
    var error: String?
    var lastRefreshDate: Date?
    var sortBy: SortCriteria = .value

    var investedAssetsDestination: InvestedAssetsDestination?

    var selectedAssetDetail: SelectedAssetDetail?
}

struct InvestedAssetsDestination: Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    let assets: [InvestedAssetRow]
    let totalInvested: Double
    let totalCurrentValue: Double
    let totalPnL: Double
    let totalPnLPercent: Double
}

struct InvestedAssetRow: Equatable, Identifiable, Sendable {
    let id: String
    let asset: String
    let tradingMode: TradingMode
    let amountInvestedUSDT: Double
    let currentValueUSDT: Double
    let unrealizedPnL: Double
    let unrealizedPnLPercent: Double

    init(asset: String, tradingMode: TradingMode, amountInvestedUSDT: Double, currentValueUSDT: Double,
         unrealizedPnL: Double = 0, unrealizedPnLPercent: Double = 0) {
        self.id = asset + tradingMode.rawValue
        self.asset = asset
        self.tradingMode = tradingMode
        self.amountInvestedUSDT = amountInvestedUSDT
        self.currentValueUSDT = currentValueUSDT
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPercent = unrealizedPnLPercent
    }
}
