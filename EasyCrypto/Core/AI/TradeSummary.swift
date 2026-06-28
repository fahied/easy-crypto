//
//  TradeSummary.swift
//  EasyCrypto
//

import Foundation

/// Aggregate statistics for a single traded symbol.
nonisolated struct SymbolSummary: Equatable, Sendable {
    let symbol: String
    let asset: String
    let tradeCount: Int
    let buyCount: Int
    let sellCount: Int
    let realizedPnL: Double
}

/// A bounded, deterministic statistical summary of the user's trade history.
///
/// This is the **privacy boundary** for the on-device AI insights feature: the
/// Foundation Models engine (ADV-AI-INSIGHTS-002) only ever reasons over a
/// `TradeSummary`, never over raw `Trade`s. The summary is bounded in size
/// regardless of ledger length — `topSymbols` is capped at `maxSymbols` — so it
/// always fits the on-device model context window.
nonisolated struct TradeSummary: Equatable, Sendable {
    /// Maximum number of per-symbol entries retained, keeping the summary bounded.
    static let maxSymbols = 10

    let totalTrades: Int
    let buyCount: Int
    let sellCount: Int
    let symbolCount: Int
    let totalRealizedPnL: Double
    /// Number of sells that closed at a profit.
    let winningSells: Int
    /// Number of sells that closed at a loss.
    let losingSells: Int
    /// Trailing run of consecutive profitable sells (0 if the most recent sell lost).
    let currentWinStreak: Int
    /// Trailing run of consecutive losing sells (0 if the most recent sell profited).
    let currentLossStreak: Int
    /// Mean span in days from first buy to last sell, across symbols that have both.
    let averageHoldingPeriodDays: Double
    /// Share of total trades concentrated in the single most-traded symbol (0...1).
    let concentrationRatio: Double
    /// Most-traded symbols, descending by trade count, capped at `maxSymbols`.
    let topSymbols: [SymbolSummary]

    static let empty = TradeSummary(
        totalTrades: 0,
        buyCount: 0,
        sellCount: 0,
        symbolCount: 0,
        totalRealizedPnL: 0,
        winningSells: 0,
        losingSells: 0,
        currentWinStreak: 0,
        currentLossStreak: 0,
        averageHoldingPeriodDays: 0,
        concentrationRatio: 0,
        topSymbols: []
    )
}
