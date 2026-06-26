//
//  TradeHistoryState.swift
//  EasyCrypto
//

import Foundation

struct TradeHistoryState: ViewState {
    var trades: [Trade] = []
    var availableCoins: [String] = []
    var selectedCoin: String?
    var isLoading: Bool = false
    var error: String?

    // MARK: - Calendar

    /// First day of the month currently shown in the calendar.
    var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())

    /// Realized P&L keyed by start-of-day, for the active coin filter.
    var dailyPnL: [Date: DailyPnL] = [:]

    /// Per-transaction breakdowns (reverse chronological) for the active coin filter.
    var details: [DayTradeDetail] = []
}

// MARK: - Calendar Helpers

extension Calendar {
    /// Returns the first moment of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}
