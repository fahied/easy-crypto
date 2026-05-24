//
//  SettingsState.swift
//  EasyCrypto
//

import Foundation

struct SettingsState: ViewState {
    var hasApiKey: Bool = false
    var connectionStatus: ConnectionStatus = .idle
    var tradeCount: Int = 0
    var syncedSymbolCount: Int = 0
    var isLoading: Bool = false
    var error: String?
    var showClearConfirmation: Bool = false
    var dataCleared: Bool = false
}
