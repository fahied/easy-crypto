//
//  CalendarMonthView.swift
//  EasyCrypto
//
//  Shared calendar month view used by TradeHistoryView and PortfolioView.
//

import SwiftUI

struct CalendarMonthView: View {
    let month: Date
    let dailyPnL: [Date: DailyPnL]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingBlankCount, id: \.self) { index in
                    Color.clear
                        .frame(height: 54)
                        .id("blank-\(index)")
                }
                ForEach(daysInMonth, id: \.self) { date in
                    dayCell(for: date)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdayLabels) { entry in
                Text(entry.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let dayNumber = calendar.component(.day, from: date)
        // Gated on tradeCount, not sellCount: a day of buys has no realized P&L but
        // still has trades to show.
        if let entry = dailyPnL[day], entry.tradeCount > 0 {
            NavigationLink(value: day) {
                DayCellContent(
                    dayNumber: dayNumber,
                    pnl: entry.sellCount > 0 ? entry.realizedPnL : nil,
                    tradeCount: entry.tradeCount
                )
            }
            .buttonStyle(.plain)
        } else {
            DayCellContent(dayNumber: dayNumber, pnl: nil)
        }
    }

    // MARK: - Date math

    private struct WeekdayLabel: Identifiable {
        let id: Int
        let symbol: String
    }

    private var weekdayLabels: [WeekdayLabel] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let reordered = Array(symbols[first...] + symbols[..<first])
        return reordered.enumerated().map { WeekdayLabel(id: $0.offset, symbol: $0.element) }
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let start = calendar.startOfMonth(for: month)
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    private var leadingBlankCount: Int {
        let start = calendar.startOfMonth(for: month)
        let weekday = calendar.component(.weekday, from: start)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

// MARK: - Day Cell Content

struct DayCellContent: View {
    let dayNumber: Int
    let pnl: Double?
    var tradeCount: Int = 0

    private var hasActivity: Bool { tradeCount > 0 }

    private var color: Color {
        guard let pnl else { return hasActivity ? Theme.accent : .clear }
        if pnl > 0 { return Theme.profit }
        if pnl < 0 { return Theme.loss }
        return Theme.neutral
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(dayNumber)")
                .font(.caption.weight(.medium))
                .foregroundStyle(pnl == nil && !hasActivity ? Color.secondary : .primary)

            if let pnl {
                Text(compactAmount(pnl))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if hasActivity {
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if pnl != nil || hasActivity {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                            .stroke(color.opacity(0.45), lineWidth: 1)
                    )
            }
        }
    }

    private func compactAmount(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : "-"
        let magnitude = abs(value)
        if magnitude >= 1000 {
            return "\(prefix)\((magnitude / 1000).formatted(.number.precision(.fractionLength(1))))k"
        }
        return "\(prefix)\(magnitude.formatted(.number.precision(.fractionLength(0))))"
    }
}
