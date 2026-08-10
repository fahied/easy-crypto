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
}
