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

/// One fired-notification record shown in the Settings notification log.
struct NotificationLogRow: Identifiable, Sendable, Equatable {
    let id: UUID
    let symbol: String      // e.g. "BTCUSDT"
    let asset: String       // e.g. "BTC"
    let title: String
    let body: String
    let direction: String   // "gain" | "loss" | "priceUp" | "priceDown"
    let value: Double       // unrealized P&L (USDT) at the time the alert fired
    let firedAt: Date
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
    var notificationLog: [NotificationLogRow] = []
    var aiInsightsEnabled: Bool = true
}
