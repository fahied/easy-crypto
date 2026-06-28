//
//  InsightRefresher.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Regenerates on-device AI insights on a best-effort 4-hour cadence from the
/// background-refresh path.
///
/// Throttles via `InsightState.lastGeneratedAt`, and no-ops early when the feature
/// toggle is off or the on-device model is unavailable (so no model work happens).
/// When it runs, it summarizes the ledger, generates insights on device, replaces the
/// persisted `TradingInsight`s, and stamps `lastGeneratedAt` — all in one save.
enum InsightRefresher {
    /// Minimum spacing between insight regenerations (approximates a 4-hour cadence).
    static let throttleInterval: TimeInterval = 4 * 60 * 60

    @MainActor
    static func run(
        modelContext: ModelContext,
        summarizer: TradePatternSummarizer,
        engine: FoundationModelInsightEngine,
        settings: InsightSettingsStore = .live(),
        now: Date = Date()
    ) async throws {
        // Gate on the feature toggle and model availability before any work.
        guard settings.isEnabled() else { return }
        if case .unavailable = engine.checkAvailability() { return }

        let states = try modelContext.fetch(FetchDescriptor<InsightState>())
        let state: InsightState
        if let existing = states.first {
            state = existing
        } else {
            state = InsightState()
            modelContext.insert(state)
        }

        // 4-hour throttle: skip if generated within the window.
        guard now.timeIntervalSince(state.lastGeneratedAt) >= throttleInterval else { return }

        let trades = try modelContext.fetch(FetchDescriptor<Trade>())
        let summary = summarizer.summarize(trades, now: now)
        let generated = try await engine.generate(summary, now)

        try modelContext.delete(model: TradingInsight.self)
        for insight in generated {
            modelContext.insert(TradingInsight(
                title: insight.title,
                body: insight.body,
                category: insight.category.rawValue,
                severity: insight.severity.rawValue,
                symbol: insight.symbol,
                generatedAt: insight.generatedAt
            ))
        }

        state.lastGeneratedAt = now
        try modelContext.save()
    }
}
