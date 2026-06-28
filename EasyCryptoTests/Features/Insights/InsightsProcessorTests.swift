//
//  InsightsProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given the Insights processor")
@MainActor
struct InsightsProcessorTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Trade.self, TradingInsight.self, InsightState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func enabledSettings(_ enabled: Bool) -> InsightSettingsStore {
        let defaults = UserDefaults(suiteName: "test-insights-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: InsightSettingsStore.key)
        return .live(defaults: defaults)
    }

    private func generated(_ title: String, severity: InsightSeverity) -> GeneratedInsight {
        GeneratedInsight(
            title: title,
            body: "body",
            category: .performance,
            severity: severity,
            symbol: nil,
            generatedAt: now
        )
    }

    private func stubEngine(
        availability: FoundationModelInsightEngine.Availability = .available,
        result: [GeneratedInsight] = [],
        throwing: Error? = nil
    ) -> FoundationModelInsightEngine {
        FoundationModelInsightEngine(
            checkAvailability: { availability },
            generate: { _, _ in
                if let throwing { throw throwing }
                return result
            }
        )
    }

    private func makeProcessor(
        container: ModelContainer,
        engine: FoundationModelInsightEngine,
        enabled: Bool = true
    ) -> InsightsProcessor {
        InsightsProcessor(
            modelContainer: container,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: engine,
            settings: enabledSettings(enabled),
            now: { self.now }
        )
    }

    @Test("When loading, then persisted insights are emitted sorted by severity")
    func loadEmitsPersistedSorted() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TradingInsight(title: "Info one", body: "b", category: "performance", severity: "info", generatedAt: now))
        context.insert(TradingInsight(title: "Critical one", body: "b", category: "risk", severity: "critical", generatedAt: now))
        try context.save()

        let processor = makeProcessor(container: container, engine: stubEngine())
        await processor.handle(.load)

        #expect(processor.state.items.count == 2)
        #expect(processor.state.items.first?.severity == .critical)
        #expect(processor.state.availability == .ready)
    }

    @Test("When refreshing while available, then engine output is persisted and stamped")
    func refreshPersistsAndStamps() async throws {
        let container = try makeContainer()
        let engine = stubEngine(result: [
            generated("Watch fees", severity: .warning),
            generated("Nice work", severity: .info),
        ])
        let processor = makeProcessor(container: container, engine: engine)

        await processor.handle(.refresh)

        #expect(processor.state.isLoading == false)
        #expect(processor.state.availability == .ready)
        #expect(processor.state.items.count == 2)
        #expect(processor.state.items.first?.severity == .warning)  // sorted above info
        #expect(processor.state.lastGeneratedAt == now)

        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 2)
        #expect(try context.fetch(FetchDescriptor<InsightState>()).first?.lastGeneratedAt == now)
    }

    @Test("When refreshing while the model is unavailable, then prior insights are kept")
    func refreshUnavailableKeepsPrior() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TradingInsight(title: "Old", body: "b", category: "behavior", severity: "info", generatedAt: now))
        try context.save()

        let engine = stubEngine(
            availability: .unavailable(reason: "Apple Intelligence off"),
            throwing: InsightEngineError.unavailable(reason: "Apple Intelligence off")
        )
        let processor = makeProcessor(container: container, engine: engine)
        await processor.handle(.load)
        await processor.handle(.refresh)

        #expect(processor.state.availability == .unavailable(reason: "Apple Intelligence off"))
        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 1)  // unchanged
    }

    @Test("When the feature is disabled, then refresh does not generate")
    func refreshDisabledNoOps() async throws {
        let container = try makeContainer()
        let engine = stubEngine(result: [generated("Should not persist", severity: .info)])
        let processor = makeProcessor(container: container, engine: engine, enabled: false)

        await processor.handle(.refresh)

        #expect(processor.state.availability == .disabled)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<TradingInsight>()) == 0)
    }
}
