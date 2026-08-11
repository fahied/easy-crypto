//
//  HoldingsListView.swift
//  EasyCrypto
//
//  Unified holdings view supporting spot, cross-margin, and isolated-margin modes.
//

import SwiftUI
import SwiftData

struct HoldingsListView: View {
    @State var processor: HoldingsProcessor

    private var state: HoldingsState { processor.state }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                tradingModeBar
                holdingsList
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Trading Mode Bar

    private var tradingModeBar: some View {
        Picker("Trading Mode", selection: Binding(
            get: { state.selectedTradingMode },
            set: { [weak processor] newMode in
                guard let processor else { return }
                processor.state.selectedTradingMode = newMode
                Task { await processor.handle(.loadHoldings) }
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
                            tradingMode: state.selectedTradingMode,
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

#Preview("Spot mode") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: PriceService(
            fetchPrices: { @Sendable symbols in
                Dictionary(uniqueKeysWithValues: symbols.map { ($0, 50000.0) })
            }
        ),
        fifoCalculator: .live,
        modelContainer: container
    )
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}

#Preview("Cross margin mode") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self, MarginBalance.self,
             CrossMarginBalance.self,
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
        marginBalanceService: MarginBalanceService(
            fetchCrossMarginAccount: {
                CrossMarginAccountData(
                    marginLevel: 3.2,
                    totalAsset: 50000,
                    totalLiability: 15000,
                    totalNetAsset: 35000,
                    totalAssetOfBtc: 0.5,
                    totalLiabilityOfBtc: 0.15,
                    totalNetAssetOfBtc: 0.4,
                    maxBorrowable: 100000,
                    maintained: 20000,
                    perAssetInterest: ["BTC": 0.001, "ETH": 0.002]
                )
            },
            fetchCrossMarginBalances: { [] },
            fetchIsolatedMarginBalances: { _ in nil }
        )
    )
    processor.state.selectedTradingMode = .crossMargin
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}

#Preview("Isolated margin mode") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, MarginBalance.self,
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
        marginBalanceService: MarginBalanceService(
            fetchCrossMarginAccount: { nil },
            fetchCrossMarginBalances: { [] },
            fetchIsolatedMarginBalances: { _ in nil }
        )
    )
    processor.state.selectedTradingMode = .isolatedMargin
    return NavigationStack {
        HoldingsListView(processor: processor)
    }
    .preferredColorScheme(.dark)
}
