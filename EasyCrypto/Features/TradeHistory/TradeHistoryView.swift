//
//  TradeHistoryView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct TradeHistoryView: View {
    @State var processor: TradeHistoryProcessor

    private var state: TradeHistoryState { processor.state }

    var body: some View {
        Group {
            if state.isLoading && state.details.isEmpty {
                loadingView
            } else if let error = state.error, state.details.isEmpty {
                errorView(error)
            } else if state.details.isEmpty && !state.isLoading {
                emptyView
            } else {
                calendarContent
            }
        }
        .navigationDestination(for: Date.self) { date in
            DayDetailView(date: date, details: processor.details(on: date))
        }
        .task {
            guard state.details.isEmpty else { return }
            await processor.handle(.loadHistory)
        }
    }

    // MARK: - Content

    private var calendarContent: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                filterChips
                monthSummary
                CalendarMonthView(
                    month: state.displayedMonth,
                    dailyPnL: state.dailyPnL
                )
                .glassCard()
                legend
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    isSelected: state.selectedCoin == nil
                ) {
                    processor.send(.filterByCoin(nil))
                }

                ForEach(state.availableCoins, id: \.self) { coin in
                    FilterChip(
                        label: coin,
                        isSelected: state.selectedCoin == coin
                    ) {
                        processor.send(.filterByCoin(coin))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Month Summary

    private var monthSummary: some View {
        let entries = state.dailyPnL.values.filter {
            Calendar.current.isDate(
                $0.date,
                equalTo: state.displayedMonth,
                toGranularity: .month
            )
        }
        let total = entries.reduce(0) { $0 + $1.realizedPnL }
        let sellCount = entries.reduce(0) { $0 + $1.sellCount }

        return HStack(alignment: .center) {
            Button {
                processor.send(.previousMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Text(state.displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                PnLLabel(value: total, showArrow: false, font: .title2.bold())
                Text(sellCount == 1 ? "1 realized trade" : "\(sellCount) realized trades")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                processor.send(.nextMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Theme.profit, label: "Profit")
            legendItem(color: Theme.loss, label: "Loss")
            Spacer()
            Text("Tap a day for details")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(color.opacity(0.6), lineWidth: 1)
                )
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Trades", systemImage: "calendar")
        } description: {
            Text("Sync your trades from the Portfolio tab to see your daily P&L calendar here.")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading trades…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                processor.send(.loadHistory)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Calendar Month View

private struct CalendarMonthView: View {
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
        let dayNumber = calendar.component(.day, from: date)
        if let entry = dailyPnL[calendar.startOfDay(for: date)], entry.sellCount > 0 {
            NavigationLink(value: calendar.startOfDay(for: date)) {
                DayCellContent(dayNumber: dayNumber, pnl: entry.realizedPnL)
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

private struct DayCellContent: View {
    let dayNumber: Int
    let pnl: Double?

    private var color: Color {
        guard let pnl else { return .clear }
        if pnl > 0 { return Theme.profit }
        if pnl < 0 { return Theme.loss }
        return Theme.neutral
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(dayNumber)")
                .font(.caption.weight(.medium))
                .foregroundStyle(pnl == nil ? Color.secondary : .primary)

            if let pnl {
                Text(compactAmount(pnl))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if pnl != nil {
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

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Theme.accent.opacity(0.2)
                        : Color.clear
                )
                .foregroundStyle(isSelected ? Theme.accent : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Theme.accent : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Calendar") {
    let container = PreviewSampleData.container
    let processor = TradeHistoryProcessor(modelContainer: container)
    return NavigationStack {
        TradeHistoryView(processor: processor)
            .navigationTitle("History")
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = TradeHistoryProcessor(modelContainer: container)
    return NavigationStack {
        TradeHistoryView(processor: processor)
            .navigationTitle("History")
    }
    .preferredColorScheme(.dark)
}
