//
//  InsightChat.swift
//  EasyCrypto
//

import Foundation
import FoundationModels

/// A single message in the on-device insights chat.
nonisolated struct InsightChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Stateful, multi-turn responder seam over the on-device model.
///
/// Each `reply(to:)` streams the **cumulative** assistant text (every value is the
/// full reply so far). Implementations keep conversation context across calls. The
/// seam lets the chat processor be unit-tested without invoking the real LLM.
protocol InsightChatResponder: AnyObject {
    func reply(to message: String) -> AsyncThrowingStream<String, Error>
}

/// Live adapter: a single persistent `LanguageModelSession` whose transcript carries
/// multi-turn context, seeded with the bounded `TradeSummary` so the assistant is
/// grounded in aggregates only — never raw trades.
final class LanguageModelChatResponder: InsightChatResponder {
    private let session: LanguageModelSession

    init(summary: TradeSummary) {
        session = LanguageModelSession(instructions: InsightChatPrompt.instructions(for: summary))
    }

    func reply(to message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: message) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Builds the grounding instructions for the chat session from a `TradeSummary`.
/// Reuses the same aggregates-only prompt body as the generated-insights flow.
nonisolated enum InsightChatPrompt {
    static func instructions(for summary: TradeSummary) -> String {
        """
        You are a helpful, concise crypto trading-journal assistant. Answer the user's
        questions about their trading using only the statistics below. Never invent
        trades, prices, or figures that are not present. If the data does not contain
        the answer, say so plainly. Keep answers short and practical, and describe
        patterns and options rather than giving prescriptive financial advice.

        \(InsightPrompt.prompt(for: summary))
        """
    }
}
