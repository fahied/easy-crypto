//
//  AccountBalance.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// The authoritative per-asset wallet balance from Binance (`free + locked`).
///
/// Persisted on each portfolio refresh so the Holdings tab — which does not run a
/// sync — can display quantities that match the Binance app offline. Holding
/// *quantity* comes from here; cost basis and realized P&L still come from FIFO
/// over the trade history.
@Model
final class AccountBalance {
    #Unique<AccountBalance>([\.asset, \.tradingMode])

    var asset: String
    var quantity: Double
    var updatedAt: Date
    var tradingMode: String

    init(
        asset: String,
        quantity: Double,
        updatedAt: Date = Date(),
        tradingMode: TradingMode = .spot
    ) {
        self.asset = asset
        self.quantity = quantity
        self.updatedAt = updatedAt
        self.tradingMode = tradingMode.rawValue
    }
    var tradingModeEnum: TradingMode {
        TradingMode(rawValue: tradingMode) ?? .spot
    }
}
