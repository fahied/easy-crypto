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
}
