//
//  InsightGeneration.swift
//  EasyCrypto
//

import Foundation
import FoundationModels

// MARK: - Typed categories / severities

/// Stable category vocabulary for a generated insight.
nonisolated enum InsightCategory: String, CaseIterable, Sendable {
    case concentration
    case performance
    case behavior
    case risk

    /// Maps free-form model output onto a known category, defaulting to `.behavior`.
    static func normalized(_ raw: String) -> InsightCategory {
        InsightCategory(rawValue: raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .behavior
    }
}

/// Stable severity vocabulary for a generated insight.
nonisolated enum InsightSeverity: String, CaseIterable, Sendable {
    case info
    case warning
    case critical

    /// Maps free-form model output onto a known severity, defaulting to `.info`.
    static func normalized(_ raw: String) -> InsightSeverity {
        InsightSeverity(rawValue: raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .info
    }
}

// MARK: - Engine output (Sendable value)

/// A validated, `Sendable` insight produced by the engine. Converted to the
/// `@Model TradingInsight` at the persistence boundary (ADV-AI-INSIGHTS-003/004) so
/// the engine can run off the main actor without touching SwiftData.
nonisolated struct GeneratedInsight: Equatable, Sendable {
    let title: String
    let body: String
    let category: InsightCategory
    let severity: InsightSeverity
    let symbol: String?
    let generatedAt: Date
}

// MARK: - Guided-generation schema

/// Typed output requested from the on-device model via guided generation.
@Generable
nonisolated struct TradingInsightDraft: Equatable {
    @Guide(description: "Concise headline, about 3 to 7 words")
    var title: String
    @Guide(description: "One or two sentences: the observation plus a concrete suggestion")
    var body: String
    @Guide(description: "Category, one of: concentration, performance, behavior, risk")
    var category: String
    @Guide(description: "Severity, one of: info, warning, critical")
    var severity: String
    @Guide(description: "Most relevant trading symbol such as BTCUSDT, or an empty string if general")
    var symbol: String
}

/// Container so the model returns a bounded batch of insights in one response.
@Generable
nonisolated struct InsightDraftBatch: Equatable {
    @Guide(description: "Between 1 and 5 insights, most important first")
    var insights: [TradingInsightDraft]
}

// MARK: - Pure mapping (drafts -> validated values)

/// Pure, AI-free normalization of raw model drafts into `GeneratedInsight` values.
/// Drops drafts with an empty title or body; normalizes category/severity onto the
/// known vocabularies; treats an empty symbol as `nil`.
nonisolated enum InsightDraftMapper {
    static func map(_ drafts: [TradingInsightDraft], now: Date) -> [GeneratedInsight] {
        drafts.compactMap { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !body.isEmpty else { return nil }

            let symbol = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return GeneratedInsight(
                title: title,
                body: body,
                category: InsightCategory.normalized(draft.category),
                severity: InsightSeverity.normalized(draft.severity),
                symbol: symbol.isEmpty ? nil : symbol,
                generatedAt: now
            )
        }
    }
}

// MARK: - Prompt construction (bounded summary only)

/// Builds the on-device model instructions and prompt from a `TradeSummary`.
/// Only aggregate statistics are included — never individual trades.
nonisolated enum InsightPrompt {
    static let instructions = """
    You are a concise crypto trading-journal assistant. Analyze the provided \
    aggregate trading statistics and surface useful patterns, risks, and concrete \
    suggestions. Only use the supplied numbers — never invent trades, prices, or \
    figures. Each insight needs a short title, a one or two sentence body, a \
    category (concentration, performance, behavior, or risk), and a severity \
    (info, warning, or critical).
    """

    static func prompt(for summary: TradeSummary) -> String {
        var lines: [String] = [
            "Trading summary (aggregates only, no individual trades):",
            "- Total trades: \(summary.totalTrades) (buys: \(summary.buyCount), sells: \(summary.sellCount))",
            "- Distinct symbols: \(summary.symbolCount)",
            "- Total realized P&L (USDT): \(format(summary.totalRealizedPnL))",
            "- Winning sells: \(summary.winningSells), losing sells: \(summary.losingSells)",
            "- Current win streak: \(summary.currentWinStreak), loss streak: \(summary.currentLossStreak)",
            "- Average holding period (days): \(format(summary.averageHoldingPeriodDays))",
            "- Concentration (share of trades in the top symbol): \(format(summary.concentrationRatio))",
        ]

        if !summary.topSymbols.isEmpty {
            lines.append("- Top symbols:")
            for symbol in summary.topSymbols {
                lines.append(
                    "  • \(symbol.symbol): \(symbol.tradeCount) trades, realized P&L \(format(symbol.realizedPnL)) USDT"
                )
            }
        }

        lines.append("")
        lines.append("Produce 1 to 5 concise, actionable insights about patterns, risks, and suggestions.")
        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
