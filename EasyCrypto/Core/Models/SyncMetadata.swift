//
//  SyncMetadata.swift
//  EasyCrypto
//

import Foundation
import SwiftData

@Model
final class SyncMetadata {
    #Unique<SyncMetadata>([\.symbol, \.tradingMode])

    var symbol: String
    var lastTradeId: Int64
    var lastSyncDate: Date
    var tradingMode: String

    init(
        symbol: String,
        lastTradeId: Int64,
        lastSyncDate: Date,
        tradingMode: TradingMode = .spot
    ) {
        self.symbol = symbol
        self.lastTradeId = lastTradeId
        self.lastSyncDate = lastSyncDate
        self.tradingMode = tradingMode.rawValue
    }
    var tradingModeEnum: TradingMode {
        TradingMode(rawValue: tradingMode) ?? .spot
    }
}
