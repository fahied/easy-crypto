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

    /// Holdings with a meaningful unrealized gain, best performer first.
    /// Gains under $1 are dust and stay out of the summary.
    var profitableHoldings: [Holding] {
        holdings
            .filter { $0.unrealizedPnL >= 1 }
            .sorted { $0.unrealizedPnLPercent > $1.unrealizedPnLPercent }
    }

    /// Combined unrealized gain of the profitable holdings only.
    var totalUnrealizedProfit: Double {
        profitableHoldings.reduce(0) { $0 + $1.unrealizedPnL }
    }
}
