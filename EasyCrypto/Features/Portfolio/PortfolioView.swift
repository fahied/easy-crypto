//
//  PortfolioView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct PortfolioView: View {
    @State var processor: PortfolioProcessor

    @State private var investedAssetsRoute = false
    @State private var investedAssetsSnapshot: InvestedAssetsDestination?

    @State private var selectedAssetRoute = false
    @State private var selectedAssetSnapshot: SelectedAssetDetail?

    private var state: PortfolioState { processor.state }

    var body: some View {
        NavigationStack {
            Group {
                if state.isLoading {
                    loadingView
                } else if let error = state.error {
                    errorView(error)
                } else if processor.aggregateSummary.isEmpty {
                    emptyView
                } else {
                    portfolioContent
                }
            }
            .navigationTitle("Portfolio")
            .navigationDestination(isPresented: $investedAssetsRoute) {
                if let destination = investedAssetsSnapshot {
                    InvestedAssetsView(
                        destination: destination,
                        onSelectAsset: { asset, tradingMode in
                            Task { await processor.handle(.showAssetDetail(asset: asset, tradingMode: tradingMode)) }
                        }
                    )
                }
            }
            .onChange(of: state.investedAssetsDestination) { _, newValue in
                if let destination = newValue {
                    investedAssetsSnapshot = destination
                    investedAssetsRoute = true
                }
            }
            .navigationDestination(isPresented: $selectedAssetRoute) {
                if let detail = selectedAssetSnapshot {
                    CoinDetailView(
                        processor: processor.makeCoinDetailProcessor(),
                        asset: detail.asset,
                        tradingMode: detail.tradingMode
                    )
                }
            }
            .onChange(of: state.selectedAssetDetail) { _, newValue in
                if let detail = newValue {
                    selectedAssetSnapshot = detail
                    selectedAssetRoute = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await processor.handle(.refresh) }
                    } label: {
                        if state.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(state.isLoading)
                }
            }
            .refreshable {
                await processor.handle(.refresh)
            }
        }
        .onAppear {
            if !state.isLoading {
                Task { await processor.handle(.loadPersisted) }
            }
        }
    }

    // MARK: - Portfolio Content

    private var portfolioContent: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                summaryGrid
                lastRefreshFooter
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        let summary = processor.aggregateSummary
        let pnlColor = summary.totalUnrealizedPnL >= 0 ? Theme.profit : Theme.loss
        let realizedColor = summary.totalRealizedPnL >= 0 ? Theme.profit : Theme.loss
        let totalPnLColor = summary.totalPnL >= 0 ? Theme.profit : Theme.loss

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.cardSpacing),
                       GridItem(.flexible(), spacing: Theme.cardSpacing)],
            spacing: Theme.cardSpacing
        ) {
            Button {
                Task { @MainActor in
                    await processor.handle(.showInvestedAssets)
                }
            } label: {
                MetricCard(
                    label: "Total Invested",
                    value: summary.totalInvestedUSDT.usdtFormatted,
                    subtitle: "\(summary.holdingsCount) asset\(summary.holdingsCount == 1 ? "" : "s")"
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                        .padding(8)
                }
            }

            MetricCard(
                label: "Current Value",
                value: summary.totalCurrentValueUSDT.usdtFormatted
            )

            MetricCard(
                label: "Total P&L",
                value: summary.totalPnL.signedUsdtFormatted,
                subtitle: summary.totalPnLPercent.percentFormatted,
                valueColor: totalPnLColor
            )

            MetricCard(
                label: "Unrealized P&L",
                value: summary.totalUnrealizedPnL.signedUsdtFormatted,
                subtitle: summary.totalUnrealizedPnLPercent.percentFormatted,
                valueColor: pnlColor
            )

            MetricCard(
                label: "Realized P&L",
                value: summary.totalRealizedPnL.signedUsdtFormatted,
                valueColor: realizedColor
            )
        }
        .animation(.spring(duration: 0.4), value: summary.totalCurrentValueUSDT)
    }

    // MARK: - Last Refresh Footer

    @ViewBuilder
    private var lastRefreshFooter: some View {
        if let date = state.lastRefreshDate {
            Text("Updated \(date.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
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
                processor.send(.refresh)
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
                processor.send(.refresh)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Previews

#Preview("Portfolio") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        apiClient: .noop,
        modelContainer: container
    )
    processor.state = PortfolioState(
        summary: PreviewSampleData.samplePortfolioSummary,
        lastRefreshDate: Date()
    )
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        apiClient: .noop,
        modelContainer: container
    )
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Loading") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        apiClient: .noop,
        modelContainer: container
    )
    processor.state.isLoading = true
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Error") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
             MarginBalance.self, CrossMarginBalance.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        apiClient: .noop,
        modelContainer: container
    )
    processor.state.error = "Failed to connect to Binance API. Please check your network connection and try again."
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}
