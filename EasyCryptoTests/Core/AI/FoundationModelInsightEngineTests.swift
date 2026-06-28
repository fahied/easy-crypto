//
//  FoundationModelInsightEngineTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given the Foundation Models insight engine")
struct FoundationModelInsightEngineTests {

    /// Fake session that records what it was asked and returns canned drafts.
    private actor FakeInsightSession: InsightDraftGenerating {
        private(set) var capturedInstructions: String?
        private(set) var capturedPrompt: String?
        private let drafts: [TradingInsightDraft]

        init(drafts: [TradingInsightDraft]) {
            self.drafts = drafts
        }

        func generateDrafts(instructions: String, prompt: String) async throws -> [TradingInsightDraft] {
            capturedInstructions = instructions
            capturedPrompt = prompt
            return drafts
        }
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(totalTrades: Int) -> TradeSummary {
        TradeSummary(
            totalTrades: totalTrades,
            buyCount: totalTrades,
            sellCount: 0,
            symbolCount: 1,
            totalRealizedPnL: 0,
            winningSells: 0,
            losingSells: 0,
            currentWinStreak: 0,
            currentLossStreak: 0,
            averageHoldingPeriodDays: 0,
            concentrationRatio: 1,
            topSymbols: []
        )
    }

    // MARK: - Pure mapping

    @Test("When drafts include invalid or empty fields, then mapping normalizes and drops them")
    func mappingNormalizesAndDrops() {
        let drafts = [
            TradingInsightDraft(
                title: "Concentration risk",
                body: "BTC dominates your trades.",
                category: "CONCENTRATION",
                severity: "Warning",
                symbol: "BTCUSDT"
            ),
            TradingInsightDraft(  // dropped: empty title
                title: "   ",
                body: "no title",
                category: "risk",
                severity: "critical",
                symbol: ""
            ),
            TradingInsightDraft(  // unknown category/severity -> defaults; empty symbol -> nil
                title: "Diversify",
                body: "Consider spreading exposure.",
                category: "totally-unknown",
                severity: "bogus",
                symbol: ""
            ),
        ]

        let mapped = InsightDraftMapper.map(drafts, now: now)

        #expect(mapped.count == 2)
        #expect(mapped[0].category == .concentration)
        #expect(mapped[0].severity == .warning)
        #expect(mapped[0].symbol == "BTCUSDT")
        #expect(mapped[0].generatedAt == now)
        #expect(mapped[1].category == .behavior)  // normalized fallback
        #expect(mapped[1].severity == .info)       // normalized fallback
        #expect(mapped[1].symbol == nil)
    }

    // MARK: - Engine generate

    @Test("When available, then generate maps drafts and passes only summary stats")
    func generateMapsDraftsFromSummaryOnly() async throws {
        let fake = FakeInsightSession(drafts: [
            TradingInsightDraft(
                title: "Watch fees",
                body: "Frequent trading raises costs.",
                category: "behavior",
                severity: "info",
                symbol: ""
            )
        ])
        let engine = FoundationModelInsightEngine.make(session: fake) { .available }

        let result = try await engine.generate(summary(totalTrades: 4), now)

        #expect(result.count == 1)
        #expect(result[0].title == "Watch fees")
        #expect(result[0].category == .behavior)

        let prompt = await fake.capturedPrompt
        let instructions = await fake.capturedInstructions
        #expect(prompt?.contains("Total trades: 4") == true)
        #expect(instructions == InsightPrompt.instructions)
    }

    @Test("When unavailable, then generate throws without calling the model")
    func generateThrowsWhenUnavailable() async {
        let fake = FakeInsightSession(drafts: [])
        let engine = FoundationModelInsightEngine.make(session: fake) {
            .unavailable(reason: "Apple Intelligence off")
        }

        await #expect(throws: InsightEngineError.unavailable(reason: "Apple Intelligence off")) {
            _ = try await engine.generate(summary(totalTrades: 1), now)
        }
        let prompt = await fake.capturedPrompt
        #expect(prompt == nil)  // model was never asked
    }

    @Test("When availability is probed, then the engine surfaces the stubbed result")
    func availabilityIsSurfaced() {
        let fake = FakeInsightSession(drafts: [])
        let engine = FoundationModelInsightEngine.make(session: fake) {
            .unavailable(reason: "device not eligible")
        }
        #expect(engine.checkAvailability() == .unavailable(reason: "device not eligible"))
    }
}
