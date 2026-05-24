//
//  PortfolioView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct PortfolioView: View {
    var processor: PortfolioProcessor

    private var state: PortfolioState { processor.state }

    var body: some View {
        NavigationStack {
            Group {
                if state.isLoading && state.holdings.isEmpty {
                    loadingView
                } else if let error = state.error, state.holdings.isEmpty {
                    errorView(error)
                } else if state.holdings.isEmpty && !state.isLoading {
                    emptyView
                } else {
                    portfolioContent
                }
            }
            .navigationTitle("Portfolio")
            .refreshable {
                await processor.handle(.refresh)
            }
        }
    }

    // MARK: - Portfolio Content

    private var portfolioContent: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                summaryGrid
                sortBar
                holdingsList
                lastRefreshFooter
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        let summary = state.summary
        let pnlColor = summary.totalUnrealizedPnL >= 0 ? Theme.profit : Theme.loss
        let realizedColor = summary.totalRealizedPnL >= 0 ? Theme.profit : Theme.loss

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.cardSpacing),
                       GridItem(.flexible(), spacing: Theme.cardSpacing)],
            spacing: Theme.cardSpacing
        ) {
            MetricCard(
                label: "Total Invested",
                value: summary.totalInvestedUSDT.usdtFormatted,
                subtitle: "\(summary.holdingsCount) assets"
            )

            MetricCard(
                label: "Current Value",
                value: summary.totalCurrentValueUSDT.usdtFormatted
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

    // MARK: - Sort Bar

    private var sortBar: some View {
        Picker("Sort by", selection: Binding(
            get: { state.sortCriteria },
            set: { processor.send(.sortHoldings(by: $0)) }
        )) {
            ForEach(SortCriteria.allCases, id: \.self) { criteria in
                Text(criteria.displayName).tag(criteria)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Holdings List

    private var holdingsList: some View {
        LazyVStack(spacing: Theme.cardSpacing) {
            ForEach(state.holdings) { holding in
                HoldingRow(holding: holding)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(duration: 0.35), value: state.holdings.map(\.asset))
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
        } actions: {
            Button("Try Again") {
                processor.send(.refresh)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Holding Row

struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack(spacing: 12) {
            // Asset icon placeholder
            Circle()
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(holding.asset.prefix(1)))
                        .font(.headline.bold())
                        .foregroundStyle(Theme.accent)
                }

            // Asset info
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.asset)
                    .font(.headline)
                Text("\(holding.totalQuantity.quantityFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Value & P&L
            VStack(alignment: .trailing, spacing: 2) {
                Text(holding.currentValueUSDT.usdtFormatted)
                    .font(.headline)
                PnLLabel(
                    value: holding.unrealizedPnL,
                    percentage: holding.unrealizedPnLPercent,
                    font: .caption.bold()
                )
            }
        }
        .glassCard()
    }
}

// MARK: - SortCriteria Display

extension SortCriteria {
    var displayName: String {
        switch self {
        case .value: "Value"
        case .name: "Name"
        case .pnl: "P&L"
        case .pnlPercent: "P&L %"
        }
    }
}

// MARK: - Previews

#Preview("Loaded with holdings") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state = PortfolioState(
        summary: PortfolioSummary(from: PreviewSampleData.sampleHoldings),
        holdings: PreviewSampleData.sampleHoldings,
        lastRefreshDate: Date()
    )
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Empty state") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Loading") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state.isLoading = true
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}

#Preview("Error") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = PortfolioProcessor(
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state.error = "Failed to connect to Binance API. Please check your network connection and try again."
    return PortfolioView(processor: processor)
        .preferredColorScheme(.dark)
}
