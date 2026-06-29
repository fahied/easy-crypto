//
//  InsightChatProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation
import os

/// Drives the on-device insights chat: owns a persistent, summary-grounded responder
/// and streams multi-turn replies into state.
///
/// Gated on the Settings toggle and model availability. The responder is built lazily
/// from a bounded `TradeSummary` (aggregates only — never raw trades). Input is
/// blocked while a response is in flight, since one session cannot service concurrent
/// requests.
@Observable
class InsightChatProcessor: Processor {
    var state = InsightChatState()

    private let modelContext: ModelContext
    private let summarizer: TradePatternSummarizer
    private let engine: FoundationModelInsightEngine
    private let makeResponder: (TradeSummary) -> any InsightChatResponder
    private let settings: InsightSettingsStore
    private let now: @Sendable () -> Date

    private var responder: (any InsightChatResponder)?

    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "insight-chat"
    )

    init(
        modelContainer: ModelContainer,
        summarizer: TradePatternSummarizer,
        engine: FoundationModelInsightEngine,
        makeResponder: @escaping (TradeSummary) -> any InsightChatResponder = { LanguageModelChatResponder(summary: $0) },
        settings: InsightSettingsStore = .live(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContext = ModelContext(modelContainer)
        self.summarizer = summarizer
        self.engine = engine
        self.makeResponder = makeResponder
        self.settings = settings
        self.now = now
    }

    func handle(_ intent: InsightChatIntent) async {
        switch intent {
        case .start:
            state.availability = currentAvailability()
        case .sendMessage(let text):
            await send(text)
        case .clear:
            responder = nil
            state.messages = []
            state.error = nil
            state.availability = currentAvailability()
        }
    }

    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard settings.isEnabled() else {
            state.availability = .disabled
            return
        }
        if case .unavailable(let reason) = engine.checkAvailability() {
            state.availability = .unavailable(reason: reason)
            return
        }
        guard !state.isResponding else { return }  // no overlapping turns

        state.availability = .ready
        state.error = nil

        // Lazily build the grounded, persistent responder on first message.
        if responder == nil {
            let trades = (try? modelContext.fetch(FetchDescriptor<Trade>())) ?? []
            responder = makeResponder(summarizer.summarize(trades, now: now()))
        }
        guard let responder else { return }

        state.inputText = ""
        state.messages.append(InsightChatMessage(role: .user, text: trimmed, timestamp: now()))

        let assistantID = UUID()
        state.messages.append(InsightChatMessage(id: assistantID, role: .assistant, text: "", timestamp: now()))
        state.isResponding = true

        do {
            for try await snapshot in responder.reply(to: trimmed) {
                if let index = state.messages.firstIndex(where: { $0.id == assistantID }) {
                    state.messages[index].text = snapshot  // cumulative text
                }
            }
        } catch {
            state.error = error.localizedDescription
            Self.logger.error("Chat reply failed: \(error.localizedDescription)")
            // Drop the placeholder if nothing streamed.
            if let index = state.messages.firstIndex(where: { $0.id == assistantID }),
               state.messages[index].text.isEmpty {
                state.messages.remove(at: index)
            }
        }

        state.isResponding = false
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
