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

    /// Higher rank surfaces first in the UI.
    var sortRank: Int {
        switch self {
        case .critical: 3
        case .warning: 2
        case .info: 1
        }
    }

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
    @Guide(description: "3 to 7 words")
    var title: String
    @Guide(description: "One or two concise sentences. State the observation first, then one practical suggestion.")
    var body: String
    @Guide(description: "Category, one of: concentration, performance, behavior, risk")
    var category: String
    @Guide(description: "Severity, one of: info, warning, critical")
    var severity: String
    @Guide(description: "Trading symbol like BTCUSDT. Use an empty string if the insight applies to all trades.")
    var symbol: String
}

/// Container so the model returns a bounded batch of insights in one response.
@Generable
nonisolated struct InsightDraftBatch: Equatable {
    @Guide(description: "Between 0 and 5 insights, most important first. Return an empty array if the statistics do not suggest any notable patterns.")
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
You are a crypto trading journal assistant.

Analyze the trading statistics provided and describe the patterns you observe.
Never assume or invent missing information.
Base every observation only on the supplied statistics.

Generate between 0 and 5 insights.

Each insight must include:
- title
- body
- category
- severity
- symbol

The category must be one of:
- concentration
- performance
- behavior
- risk

The severity must be one of:
- info
- warning
- critical

Keep every insight concise and descriptive.
Order insights from highest impact to lowest.
Describe what the numbers show; do not make trading recommendations.

These observations are for informational purposes only and do not constitute financial advice.
"""

    static func prompt(for summary: TradeSummary) -> String {
        let decidedSells = summary.winningSells + summary.losingSells
        var lines: [String] = [
            "Trading statistics (aggregated, no individual trades):",
            "- Total trades: \(summary.totalTrades) (buys: \(summary.buyCount), sells: \(summary.sellCount))",
            "- Distinct symbols: \(summary.symbolCount)",
            "- Total realized P&L: \(number(summary.totalRealizedPnL)) USDT",
        ]

        if summary.sellCount > 0 {
            let perSell = summary.totalRealizedPnL / Double(summary.sellCount)
            lines.append("- Average realized P&L per sell: \(number(perSell)) USDT")
        }
        if decidedSells > 0 {
            let winRate = Double(summary.winningSells) / Double(decidedSells)
            lines.append(
                "- Win rate: \(percent(winRate)) (\(summary.winningSells) winning, \(summary.losingSells) losing sells)"
            )
        }
        lines.append("- Current win streak: \(summary.currentWinStreak), loss streak: \(summary.currentLossStreak)")
        lines.append("- Average holding period: \(number(summary.averageHoldingPeriodDays)) days")
        lines.append("- Trade concentration: \(percent(summary.concentrationRatio)) of trades are in the top symbol")

        if !summary.topSymbols.isEmpty {
            lines.append("- Top symbols:")
            for symbol in summary.topSymbols {
                lines.append("  \(symbol.symbol)")
                lines.append("  - trades: \(symbol.tradeCount)")
                lines.append("  - realized P&L: \(number(symbol.realizedPnL)) USDT")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private static func percent(_ ratio: Double) -> String {
        ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}
