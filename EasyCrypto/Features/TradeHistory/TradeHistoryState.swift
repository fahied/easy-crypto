//
//  TradeHistoryState.swift
//  EasyCrypto
//

import Foundation

struct TradeHistoryState: ViewState {
    var trades: [Trade] = []
    var availableCoins: [String] = []
    var selectedCoin: String?
    var isLoading: Bool = false
    var error: String?
}
