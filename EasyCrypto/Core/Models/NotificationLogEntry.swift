//
//  NotificationLogEntry.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// A persisted record of a local notification that was delivered to the user.
///
/// One entry is written each time a price alert fires and a notification is
/// actually delivered (gain, loss, price-up, price-down). Silent reference-price
/// seeding does not produce an entry. Entries are browsable from Settings.
@Model
final class NotificationLogEntry {
    var id: UUID
    var symbol: String          // e.g. "BTCUSDT"
    var asset: String           // e.g. "BTC"
    var title: String           // delivered notification title
    var body: String            // delivered notification body
    var direction: String       // "gain" | "loss" | "priceUp" | "priceDown"
    var value: Double           // unrealized P&L (USDT) at the time the alert fired
    var firedAt: Date

    init(
        id: UUID = UUID(),
        symbol: String,
        asset: String,
        title: String,
        body: String,
        direction: String,
        value: Double,
        firedAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.asset = asset
        self.title = title
        self.body = body
        self.direction = direction
        self.value = value
        self.firedAt = firedAt
    }
}
