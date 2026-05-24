//
//  CoinDetailView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData
import Charts

struct CoinDetailView: View {
    var processor: CoinDetailProcessor
    let asset: String

    private var state: CoinDetailState { processor.state }

    var body: some View {
        Group {
            if state.isLoading && state.holding == nil {
                loadingView
            } else if let error = state.error, state.holding == nil {
                errorView(error)
            } else {
                detailContent
            }
        }
        .navigationTitle(asset)
        .task {
            guard state.holding == nil else { return }
            await processor.handle(.loadDetail(asset: asset))
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                if let holding = state.holding {
                    summaryCard(holding)
                }
                chartSection
                tradesSection
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Summary Card

    private func summaryCard(_ holding: Holding) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(holding.asset)
                        .font(.title2.bold())
                    Text("\(holding.totalQuantity.quantityFormatted) units")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(holding.currentPrice.usdtFormatted)
                        .font(.title2.bold())
                    Text("Current Price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.3)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                detailMetric("Avg Cost", holding.weightedAvgBuyPrice.usdtFormatted)
                detailMetric("Invested", holding.totalInvestedUSDT.usdtFormatted)
                detailMetric("Value", holding.currentValueUSDT.usdtFormatted)
                detailMetric(
                    "Unrealized",
                    holding.unrealizedPnL.signedUsdtFormatted,
                    color: holding.unrealizedPnL >= 0 ? Theme.profit : Theme.loss
                )
            }

            if holding.realizedPnL != 0 {
                HStack {
                    Text("Realized P&L")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PnLLabel(
                        value: holding.realizedPnL,
                        showArrow: true,
                        font: .subheadline.bold()
                    )
                }
            }
        }
        .glassCard()
    }

    private func detailMetric(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(spacing: 12) {
            // Interval picker
            Picker("Interval", selection: Binding(
                get: { state.chartInterval },
                set: { processor.send(.changeChartInterval($0)) }
            )) {
                ForEach(ChartInterval.allCases, id: \.self) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .pickerStyle(.segmented)

            // Chart
            if state.klines.isEmpty {
                Text("No chart data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else {
                priceChart
            }
        }
        .glassCard()
    }

    private var priceChart: some View {
        Chart(state.klines) { kline in
            LineMark(
                x: .value("Time", kline.openDate),
                y: .value("Price", kline.close)
            )
            .foregroundStyle(Theme.accent)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", kline.openDate),
                y: .value("Price", kline.close)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) {
                AxisValueLabel()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 200)
    }

    // MARK: - Trades Section

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trade History")
                .font(.headline)

            if state.trades.isEmpty {
                Text("No trades recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(state.trades, id: \.binanceTradeId) { trade in
                        TradeRowView(
                            date: trade.timestamp,
                            isBuyer: trade.isBuyer,
                            price: trade.price,
                            quantity: trade.quantity,
                            total: trade.quoteQuantity
                        )
                        if trade.binanceTradeId != state.trades.last?.binanceTradeId {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading \(asset) details…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}

// MARK: - Previews

#Preview("With chart data") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = CoinDetailProcessor(
        apiClient: .preview,
        priceService: .preview,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state = CoinDetailState(
        asset: "BTC",
        holding: PreviewSampleData.sampleHoldings[0],
        trades: PreviewSampleData.sampleTrades.filter { $0.asset == "BTC" },
        klines: PreviewSampleData.sampleKlines
    )
    return NavigationStack {
        CoinDetailView(processor: processor, asset: "BTC")
    }
    .preferredColorScheme(.dark)
}

#Preview("Without chart data") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = CoinDetailProcessor(
        apiClient: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state = CoinDetailState(
        asset: "ETH",
        holding: PreviewSampleData.sampleHoldings[1],
        trades: PreviewSampleData.sampleTrades.filter { $0.asset == "ETH" }
    )
    return NavigationStack {
        CoinDetailView(processor: processor, asset: "ETH")
    }
    .preferredColorScheme(.dark)
}

#Preview("Loading") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = CoinDetailProcessor(
        apiClient: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state.isLoading = true
    return NavigationStack {
        CoinDetailView(processor: processor, asset: "BTC")
    }
    .preferredColorScheme(.dark)
}
