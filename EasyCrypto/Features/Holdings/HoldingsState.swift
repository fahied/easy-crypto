//
//  HoldingsState.swift
//  EasyCrypto
//

import Foundation

struct HoldingsState: ViewState {
    var holdings: [Holding] = []
    var isLoading: Bool = false
    var error: String?

    var selectedTradingMode: TradingMode = .spot
    var lastRefreshDate: Date? = nil

    /// Holdings with any positive unrealized gain, best performer first.
    var profitableHoldings: [Holding] {
        holdings
            .filter { $0.unrealizedPnL > 0 }
            .sorted { $0.unrealizedPnLPercent > $1.unrealizedPnLPercent }
    }

    /// Combined unrealized gain of the profitable holdings only.
    var totalUnrealizedProfit: Double {
        profitableHoldings.reduce(0) { $0 + $1.unrealizedPnL }
    }
}
