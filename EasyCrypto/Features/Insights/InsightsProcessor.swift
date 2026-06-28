//
//  InsightsProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation
import os

/// Drives the Insights surface: loads persisted insights and, on refresh, runs the
/// on-device engine over a fresh `TradeSummary` and replaces the stored insights.
///
/// This is the persistence boundary: the engine returns `Sendable GeneratedInsight`
/// values and this processor (on the main actor) creates the `@Model TradingInsight`
/// rows. Generation is gated on the Settings toggle and on model availability.
@Observable
class InsightsProcessor: Processor {
    var state = InsightsState()

    private let modelContext: ModelContext
    private let summarizer: TradePatternSummarizer
    private let engine: FoundationModelInsightEngine
    private let settings: InsightSettingsStore
    private let now: @Sendable () -> Date

    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "insights"
    )

    init(
        modelContainer: ModelContainer,
        summarizer: TradePatternSummarizer,
        engine: FoundationModelInsightEngine,
        settings: InsightSettingsStore = .live(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContext = ModelContext(modelContainer)
        self.summarizer = summarizer
        self.engine = engine
        self.settings = settings
        self.now = now
    }

    func handle(_ intent: InsightsIntent) async {
        switch intent {
        case .load:
            await load()
        case .refresh:
            await refresh()
        }
    }

    // MARK: - Load

    private func load() async {
        do {
            state.items = try loadPersistedItems()
            state.lastGeneratedAt = try loadLastGeneratedAt()
        } catch {
            state.error = error.localizedDescription
        }
        state.availability = currentAvailability()
    }

    // MARK: - Refresh

    private func refresh() async {
        guard settings.isEnabled() else {
            state.availability = .disabled
            return
        }
        if case .unavailable(let reason) = engine.checkAvailability() {
            state.availability = .unavailable(reason: reason)
            return
        }

        state.isLoading = true
        state.error = nil

        do {
            let trades = try modelContext.fetch(FetchDescriptor<Trade>())
            let summary = summarizer.summarize(trades, now: now())
            let generated = try await engine.generate(summary, now())
            try replacePersistedInsights(with: generated)
            state.items = try loadPersistedItems()
            state.lastGeneratedAt = try loadLastGeneratedAt()
            state.availability = .ready
            Self.logger.info("Generated \(generated.count) insights on device")
        } catch let error as InsightEngineError {
            if case .unavailable(let reason) = error {
                state.availability = .unavailable(reason: reason)
            }
        } catch {
            state.error = error.localizedDescription
            Self.logger.error("Insight generation failed: \(error.localizedDescription)")
        }

        state.isLoading = false
    }

    // MARK: - Persistence

    private func loadPersistedItems() throws -> [InsightItem] {
        let models = try modelContext.fetch(FetchDescriptor<TradingInsight>())
        return models
            .map(InsightItem.init)
            .sorted { lhs, rhs in
                lhs.severity.sortRank != rhs.severity.sortRank
                    ? lhs.severity.sortRank > rhs.severity.sortRank
                    : lhs.generatedAt > rhs.generatedAt
            }
    }

    private func loadLastGeneratedAt() throws -> Date? {
        let states = try modelContext.fetch(FetchDescriptor<InsightState>())
        let stamp = states.first?.lastGeneratedAt
        return stamp == .distantPast ? nil : stamp
    }

    private func replacePersistedInsights(with generated: [GeneratedInsight]) throws {
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

        let states = try modelContext.fetch(FetchDescriptor<InsightState>())
        if let existing = states.first {
            existing.lastGeneratedAt = now()
        } else {
            modelContext.insert(InsightState(lastGeneratedAt: now()))
        }
        try modelContext.save()
    }

    private func currentAvailability() -> InsightsAvailability {
        guard settings.isEnabled() else { return .disabled }
        switch engine.checkAvailability() {
        case .available:
            return .ready
        case .unavailable(let reason):
            return .unavailable(reason: reason)
        }
    }
}
