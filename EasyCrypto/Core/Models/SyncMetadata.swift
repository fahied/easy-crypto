//
//  SyncMetadata.swift
//  EasyCrypto
//

import Foundation
import SwiftData

@Model
final class SyncMetadata {
    #Unique<SyncMetadata>([\.symbol])

    var symbol: String
    var lastTradeId: Int64
    var lastSyncDate: Date

    init(symbol: String, lastTradeId: Int64, lastSyncDate: Date) {
        self.symbol = symbol
        self.lastTradeId = lastTradeId
        self.lastSyncDate = lastSyncDate
    }
}
