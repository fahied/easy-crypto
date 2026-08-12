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
                holdingsList
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Show cached data immediately; Refresh Now triggers full exchange sync.
            if !state.isLoading {
                processor.send(.loadPersisted)
            }
        }
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
