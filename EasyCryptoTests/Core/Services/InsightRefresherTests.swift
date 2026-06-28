//
//  InsightRefresherTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given the InsightRefresher")
@MainActor
struct InsightRefresherTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Trade.self, TradingInsight.self, InsightState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func settings(_ enabled: Bool) -> InsightSettingsStore {
        let defaults = UserDefaults(suiteName: "test-refresher-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: InsightSettingsStore.key)
        return .live(defaults: defaults)
    }

    private func stubEngine(
        availability: FoundationModelInsightEngine.Availability = .available,
        result: [GeneratedInsight]
    ) -> FoundationModelInsightEngine {
        FoundationModelInsightEngine(
            checkAvailability: { availability },
            generate: { _, _ in result }
        )
    }

    private var oneInsight: [GeneratedInsight] {
        [GeneratedInsight(
            title: "Diversify",
            body: "Spread exposure.",
            category: .risk,
            severity: .warning,
            symbol: nil,
            generatedAt: now
        )]
    }

    @Test("When generated within 4 hours, then it skips")
    func skipsWithinWindow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(InsightState(lastGeneratedAt: now.addingTimeInterval(-60 * 60)))  // 1h ago
        try context.save()

        try await InsightRefresher.run(
            modelContext: context,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: stubEngine(result: oneInsight),
            settings: settings(true),
            now: now
        )

        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 0)
    }

    @Test("When the window has elapsed, then it regenerates and stamps the timestamp")
    func regeneratesAfterWindow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(InsightState(lastGeneratedAt: now.addingTimeInterval(-5 * 60 * 60)))  // 5h ago
        try context.save()

        try await InsightRefresher.run(
            modelContext: context,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: stubEngine(result: oneInsight),
            settings: settings(true),
            now: now
        )

        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 1)
        #expect(try context.fetch(FetchDescriptor<InsightState>()).first?.lastGeneratedAt == now)
    }

    @Test("When the toggle is off, then it does nothing")
    func disabledNoOps() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        try await InsightRefresher.run(
            modelContext: context,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: stubEngine(result: oneInsight),
            settings: settings(false),
            now: now
        )

        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<InsightState>()) == 0)
    }

    @Test("When the model is unavailable, then it does nothing")
    func unavailableNoOps() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        try await InsightRefresher.run(
            modelContext: context,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: stubEngine(availability: .unavailable(reason: "off"), result: oneInsight),
            settings: settings(true),
            now: now
        )

        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<InsightState>()) == 0)
    }
}
