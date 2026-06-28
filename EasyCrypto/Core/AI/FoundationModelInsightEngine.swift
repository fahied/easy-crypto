//
//  FoundationModelInsightEngine.swift
//  EasyCrypto
//

import Foundation
import FoundationModels

// MARK: - Errors

nonisolated enum InsightEngineError: Error, Equatable {
    case unavailable(reason: String)
}

// MARK: - Session seam

/// Protocol seam over the on-device model so the engine is testable without
/// invoking the real LLM. The production adapter wraps `LanguageModelSession`.
nonisolated protocol InsightDraftGenerating: Sendable {
    func generateDrafts(instructions: String, prompt: String) async throws -> [TradingInsightDraft]
}

/// Live adapter: runs guided generation on Apple's on-device `SystemLanguageModel`.
nonisolated struct LanguageModelInsightSession: InsightDraftGenerating {
    func generateDrafts(instructions: String, prompt: String) async throws -> [TradingInsightDraft] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: InsightDraftBatch.self)
        return response.content.insights
    }
}

// MARK: - Engine

/// Turns a bounded `TradeSummary` into validated `GeneratedInsight`s using the
/// on-device model — entirely on device, no network, no remote fallback.
///
/// `generate` gates on `checkAvailability`: when the model is unavailable it throws
/// `InsightEngineError.unavailable` *without* calling the model, so unsupported
/// devices degrade gracefully. Only the bounded `TradeSummary` is ever passed to the
/// session (never raw trades).
nonisolated struct FoundationModelInsightEngine: Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable(reason: String)
    }

    var checkAvailability: @Sendable () -> Availability
    var generate: @Sendable (_ summary: TradeSummary, _ now: Date) async throws -> [GeneratedInsight]
}

extension FoundationModelInsightEngine {
    /// Composes an engine from a session seam and an availability probe. Used by both
    /// `.live` and tests (which inject a fake session + stubbed availability).
    nonisolated static func make(
        session: any InsightDraftGenerating,
        checkAvailability: @escaping @Sendable () -> Availability
    ) -> FoundationModelInsightEngine {
        FoundationModelInsightEngine(
            checkAvailability: checkAvailability,
            generate: { summary, now in
                if case .unavailable(let reason) = checkAvailability() {
                    throw InsightEngineError.unavailable(reason: reason)
                }
                let drafts = try await session.generateDrafts(
                    instructions: InsightPrompt.instructions,
                    prompt: InsightPrompt.prompt(for: summary)
                )
                return InsightDraftMapper.map(drafts, now: now)
            }
        )
    }

    /// Production engine backed by `SystemLanguageModel.default`.
    nonisolated static var live: FoundationModelInsightEngine {
        make(
            session: LanguageModelInsightSession(),
            checkAvailability: {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return .available
                case .unavailable(let reason):
                    return .unavailable(reason: describe(reason))
                }
            }
        )
    }

    nonisolated private static func describe(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to generate insights."
        case .modelNotReady:
            return "The on-device model is still preparing. Try again shortly."
        @unknown default:
            return "On-device AI is currently unavailable."
        }
    }
}
