//
//  TradeHistoryView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData
import Observation

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
