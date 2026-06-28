//
//  TradingInsight.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// A persisted AI-generated insight derived from the user's local trade history.
///
/// Insights are produced on-device (Apple Foundation Models) from a bounded
/// `TradeSummary` — never from raw trades. `category` and `severity` are stored as
/// strings (mirroring `NotificationLogEntry.direction`); typed accessors live in the
/// ai-insights layer.
///
/// - `category`: "concentration" | "performance" | "behavior" | "risk"
/// - `severity`: "info" | "warning" | "critical"
@Model
final class TradingInsight {
    var id: UUID
    var title: String
    var body: String
    var category: String
    var severity: String
    var symbol: String?         // optional symbol the insight is about, e.g. "BTCUSDT"
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: String,
        severity: String,
        symbol: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.severity = severity
        self.symbol = symbol
        self.generatedAt = generatedAt
    }
}
