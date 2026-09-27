//
//  DailyPnL.swift
//  EasyCrypto
//

import Foundation

/// Realized profit/loss aggregated for a single calendar day.
nonisolated struct DailyPnL: Equatable, Sendable {
    /// Start of the day this entry represents.
    let date: Date
    /// Net realized P&L from all sells that settled on this day (before borrowing fee deduction).
    let realizedPnL: Double
    /// Borrowing fees deducted for the day (margin trades only).
    let borrowingFeeUSDT: Double
    /// Net realized P&L after borrowing fee deduction.
    var netPnL: Double { realizedPnL - borrowingFeeUSDT }
    /// Number of sell trades on this day.
    let sellCount: Int
    /// Total number of trades (buys + sells) on this day.
    let tradeCount: Int
}

/// A single transaction enriched with FIFO cost-basis details for the day breakdown.
nonisolated struct DayTradeDetail: Identifiable, Equatable, Sendable {
    let id: String
    let asset: String
    let symbol: String
    let timestamp: Date
    let isBuyer: Bool
    let tradingMode: TradingMode
    let price: Double
    let quantity: Double
    let total: Double
    let costBasisPrice: Double?
    let invested: Double?
    let realizedPnL: Double?
    let borrowingFee: Double?
    let marginAdjustedPnL: Double?
    /// Trade-level commission/fee in USDT equivalent.
    let commission: Double?
}
