//
//  SettingsState.swift
//  EasyCrypto
//

import Foundation

/// One configurable per-coin price alert shown in Settings.
struct PriceAlertRow: Identifiable, Sendable, Equatable {
    var id: String { symbol }
    let symbol: String      // e.g. "BTCUSDT"
    let asset: String       // e.g. "BTC"
    var isEnabled: Bool
    var thresholdUSD: Double
    var percentThreshold: Double
}

struct SettingsState: ViewState {
    var hasApiKey: Bool = false
    var connectionStatus: ConnectionStatus = .idle
    var tradeCount: Int = 0
    var syncedSymbolCount: Int = 0
    var isLoading: Bool = false
    var error: String?
    var showClearConfirmation: Bool = false
    var dataCleared: Bool = false
    var notificationsAuthorized: Bool = false
    var alertRows: [PriceAlertRow] = []
}
