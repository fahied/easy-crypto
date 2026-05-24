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
            if state.isLoading && state.trades.isEmpty {
                loadingView
            } else if let error = state.error, state.trades.isEmpty {
                errorView(error)
            } else if state.trades.isEmpty && !state.isLoading {
                emptyView
            } else {
                tradeContent
            }
        }
        .task {
            guard state.trades.isEmpty else { return }
            await processor.handle(.loadHistory)
        }
    }

    // MARK: - Content

    private var tradeContent: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                filterChips
                tradeList
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

    // MARK: - Trade List (grouped by date)

    private var tradeList: some View {
        let grouped = Dictionary(grouping: state.trades) { trade in
            Calendar.current.startOfDay(for: trade.timestamp)
        }
        let sortedDates = grouped.keys.sorted(by: >)

        return LazyVStack(spacing: Theme.sectionSpacing) {
            ForEach(sortedDates, id: \.self) { date in
                VStack(alignment: .leading, spacing: 8) {
                    Text(date.formatted(date: .long, time: .omitted))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        if let trades = grouped[date] {
                            ForEach(trades, id: \.binanceTradeId) { trade in
                                TradeRowView(
                                    date: trade.timestamp,
                                    isBuyer: trade.isBuyer,
                                    price: trade.price,
                                    quantity: trade.quantity,
                                    total: trade.quoteQuantity
                                )
                                if trade.binanceTradeId != trades.last?.binanceTradeId {
                                    Divider().opacity(0.2)
                                }
                            }
                        }
                    }
                    .glassCard()
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Trades", systemImage: "arrow.left.arrow.right")
        } description: {
            Text("Sync your trades from the Portfolio tab to see history here.")
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

#Preview("All trades") {
    let container = PreviewSampleData.container
    let processor = TradeHistoryProcessor(modelContainer: container)
    return NavigationStack {
        TradeHistoryView(processor: processor)
            .navigationTitle("History")
    }
    .preferredColorScheme(.dark)
}

#Preview("Filtered by coin") {
    let container = PreviewSampleData.container
    let processor = TradeHistoryProcessor(modelContainer: container)
    processor.state.trades = PreviewSampleData.sampleTrades.filter { $0.asset == "BTC" }
    processor.state.availableCoins = ["BTC", "ETH", "SOL"]
    processor.state.selectedCoin = "BTC"
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
