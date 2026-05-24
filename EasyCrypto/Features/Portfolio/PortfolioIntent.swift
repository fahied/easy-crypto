//
//  PortfolioIntent.swift
//  EasyCrypto
//

import Foundation

enum SortCriteria: Sendable, CaseIterable {
    case value
    case name
    case pnl
    case pnlPercent
}

enum PortfolioIntent: Intent {
    case refresh
    case sortHoldings(by: SortCriteria)
}
