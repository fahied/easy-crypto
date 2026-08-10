//
//  DailyPnL.swift
//  EasyCrypto
//

import Foundation

/// Realized profit/loss aggregated for a single calendar day.
nonisolated struct DailyPnL: Equatable, Sendable {
    /// Start of the day this entry represents.
    let date: Date
    /// Net realized P&L from all sells that settled on this day.
    let realizedPnL: Double
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
    /// Executed price of the trade (buy price for buys, sell price for sells).
    let price: Double
    let quantity: Double
    /// Quote quantity in USDT for the executed trade.
    let total: Double
    /// Weighted average buy price of the lots consumed (sells only).
    let costBasisPrice: Double?
    /// USDT originally invested in this transaction.
    /// Buys: the quote quantity. Sells: the cost basis of the quantity sold.
    let invested: Double?
    /// Realized profit/loss for this transaction (sells only).
    let realizedPnL: Double?
    /// Borrowing fee deducted for this sell (margin trades only; nil for spot).
    let borrowingFee: Double?
    /// P&L after borrowing fee deduction (margin sells only; nil for spot/buys).
    let marginAdjustedPnL: Double?
}
