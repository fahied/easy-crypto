//
//  InsightsState.swift
//  EasyCrypto
//

import Foundation

/// A single AI-generated insight prepared for display.
struct InsightItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let category: InsightCategory
    let severity: InsightSeverity
    let symbol: String?
    let generatedAt: Date

    init(_ model: TradingInsight) {
        self.id = model.id
        self.title = model.title
        self.body = model.body
        self.category = InsightCategory.normalized(model.category)
        self.severity = InsightSeverity.normalized(model.severity)
        self.symbol = model.symbol
        self.generatedAt = model.generatedAt
    }
}

/// Whether the Insights surface can currently generate insights.
enum InsightsAvailability: Equatable, Sendable {
    /// On-device model is available and the feature is enabled.
    case ready
    /// The feature is turned off in Settings.
    case disabled
    /// The on-device model is unavailable (with a user-facing reason).
    case unavailable(reason: String)
}

struct InsightsState: ViewState {
    var items: [InsightItem] = []
    var isLoading: Bool = false
    var availability: InsightsAvailability = .ready
    var error: String?
    var lastGeneratedAt: Date?
    var tradeSummary: TradeSummary = .empty
}
