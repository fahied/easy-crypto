//
//  HoldingsListView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct HoldingsListView: View {
    @State var processor: HoldingsProcessor
    var onSelectHolding: (Holding) -> Void

    private var state: HoldingsState { processor.state }

    var body: some View {
        Group {
            if state.isLoading && state.holdings.isEmpty {
                loadingView
            } else if let error = state.error, state.holdings.isEmpty {
                errorView(error)
            } else if state.holdings.isEmpty && !state.isLoading {
                emptyView
            } else {
                holdingsList
            }
        }
        .task {
            guard state.holdings.isEmpty else { return }
            await processor.handle(.loadHoldings)
        }
    }

    // MARK: - Holdings List

    private var holdingsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.cardSpacing) {
                ForEach(state.holdings) { holding in
                    Button {
                        onSelectHolding(holding)
                    } label: {
                        HoldingRow(holding: holding)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Holdings", systemImage: "chart.bar")
        } description: {
            Text("Sync your trades from the Portfolio tab to see holdings here.")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading holdings…")
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
                processor.send(.loadHoldings)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Previews

#Preview("Multiple coins") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state.holdings = PreviewSampleData.sampleHoldings
    return NavigationStack {
        HoldingsListView(processor: processor, onSelectHolding: { _ in })
            .navigationTitle("Holdings")
    }
    .preferredColorScheme(.dark)
}

#Preview("Single coin") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    processor.state.holdings = [PreviewSampleData.sampleHoldings[0]]
    return NavigationStack {
        HoldingsListView(processor: processor, onSelectHolding: { _ in })
            .navigationTitle("Holdings")
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = HoldingsProcessor(
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    return NavigationStack {
        HoldingsListView(processor: processor, onSelectHolding: { _ in })
            .navigationTitle("Holdings")
    }
    .preferredColorScheme(.dark)
}
