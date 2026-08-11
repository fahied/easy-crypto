//
//  PortfolioState.swift
//  EasyCrypto
//

import Foundation

// MARK: - Portfolio Tab

enum PortfolioTab: String, CaseIterable, Sendable {
    case overview = "Overview"
    case spot = "Spot"
    case crossMargin = "Cross Margin"
    case isolatedMargin = "Isolated Margin"
}

// MARK: - Portfolio State

struct PortfolioState: ViewState {
    var summary: PortfolioSummary = .empty
    var isLoading: Bool = false
    var error: String?
    var lastRefreshDate: Date?
    var sortBy: SortCriteria = .value
    var selectedTab: PortfolioTab = .overview
}
