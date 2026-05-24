//
//  PortfolioState.swift
//  EasyCrypto
//

import Foundation

struct PortfolioState: ViewState {
    var summary: PortfolioSummary = .empty
    var holdings: [Holding] = []
    var isLoading: Bool = false
    var error: String?
    var lastRefreshDate: Date?
    var sortCriteria: SortCriteria = .value
}
