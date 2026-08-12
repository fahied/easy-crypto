//
//  HoldingsListView.swift
//  EasyCrypto
//
//  Displays aggregated holdings across spot, cross-margin, and isolated-margin.
//

import SwiftUI
import SwiftData

struct HoldingsListView: View {
    @State var processor: HoldingsProcessor

    private var state: HoldingsState { processor.state }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                tradingModePicker
                profitSummary
                holdingsList
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
        }
        .onAppear {
            // Show cached data immediately; the refresh button triggers a full sync.
            if !state.isLoading {
                processor.send(.loadPersisted)
            }
        }
    }

    // MARK: - Refresh

    private var refreshButton: some View {
        Button {
            processor.send(.loadHoldings)
        } label: {
            if state.isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(state.isLoading)
        .tint(Theme.accent)
        .accessibilityLabel("Refresh holdings")
    }

    // MARK: - In Profit Summary

    @ViewBuilder
    private var profitSummary: some View {
        let winners = state.profitableHoldings
        if !winners.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("IN PROFIT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(winners.count) of \(state.holdings.count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text(state.totalUnrealizedProfit.signedUsdtFormatted)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.profit)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(winners) { holding in
                            winnerChip(holding)
                        }
                    }
                }
            }
            .glassCard(cornerRadius: Theme.smallRadius + 4, padding: 12)
        }
    }

    private func winnerChip(_ holding: Holding) -> some View {
        HStack(spacing: 4) {
            Text(holding.asset)
            Text(holding.unrealizedPnLPercent.percentFormatted)
                .monospacedDigit()
                .foregroundStyle(Theme.profit)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(Theme.profit.opacity(0.12))
        }
        .overlay {
            Capsule().strokeBorder(Theme.profit.opacity(0.25), lineWidth: 0.5)
        }
    }

    // MARK: - Trading Mode Picker

    private var tradingModePicker: some View {
        Picker("Trading Mode", selection: Binding(
            get: { state.selectedTradingMode },
            set: { [weak processor] newMode in
                guard let processor else { return }
                processor.state.selectedTradingMode = newMode
                Task { await processor.handle(.filterByMode(newMode)) }
            }
        )) {
            ForEach(TradingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Holdings List

    private var holdingsList: some View {
        Group {
            if state.isLoading && state.holdings.isEmpty {
                loadingView
            } else if let error = state.error, state.holdings.isEmpty {
                errorView(error)
            } else if state.holdings.isEmpty && !state.isLoading {
                emptyView
            } else {
                LazyVStack(spacing: Theme.cardSpacing) {
                    ForEach(state.holdings) { holding in
                        MarginHoldingRow(
                            holding: holding,
                            tradingMode: holding.tradingMode,
                            borrowedQuantity: holding.borrowedQuantity,
                            liquidationPrice: holding.liquidationPrice.map { String(format: "%.0f", $0) }
                        )
                    }
                }
                .animation(.spring(duration: 0.35), value: state.holdings.map(\.asset))
            }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Holdings", systemImage: "chart.pie")
        } description: {
            Text("Pull down to refresh and sync your trades from Binance.")
        } actions: {
            Button("Refresh Now") {
                processor.send(.loadHoldings)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Syncing trades…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .multilineTextAlignment(.center)
        } actions: {
            Button("Try Again") {
                processor.send(.loadHoldings)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Previews

#Preview("Holdings") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: PriceService(
            fetchPrices: { @Sendable symbols in
                Dictionary(uniqueKeysWithValues: symbols.map { ($0, 50000.0) })
            }
        ),
        fifoCalculator: .live,
        modelContainer: container,
        marginTradeImportService: .noop,
        marginBalanceService: .noop
    )
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}

#Preview("Holdings empty") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: PriceService(
            fetchPrices: { @Sendable symbols in
                Dictionary(uniqueKeysWithValues: symbols.map { ($0, 50000.0) })
            }
        ),
        fifoCalculator: .live,
        modelContainer: container,
        marginTradeImportService: .noop,
        marginBalanceService: .noop
    )
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}

#Preview("Holdings loading") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: PriceService(
            fetchPrices: { @Sendable symbols in
                Dictionary(uniqueKeysWithValues: symbols.map { ($0, 50000.0) })
            }
        ),
        fifoCalculator: .live,
        modelContainer: container,
        marginTradeImportService: .noop,
        marginBalanceService: .noop
    )
    processor.state.isLoading = true
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}
