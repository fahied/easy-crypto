//
//  ContentView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var keychainService: KeychainService
    var apiClient: BinanceAPIClient
    var tradeImportService: TradeImportService
    var priceService: PriceService
    var fifoCalculator: FIFOCalculator
    var modelContainer: ModelContainer

    @State private var selectedTab: AppTab = .portfolio
    @State private var hasApiKey: Bool? = nil

    var body: some View {
        Group {
            if let hasKey = hasApiKey {
                if hasKey {
                    mainTabView
                } else {
                    onboardingView
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            checkApiKey()
        }
    }

    // MARK: - Tab View

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Portfolio", systemImage: "chart.pie.fill", value: .portfolio) {
                NavigationStack {
                    PortfolioView(
                        processor: PortfolioProcessor(
                            tradeImportService: tradeImportService,
                            priceService: priceService,
                            fifoCalculator: fifoCalculator,
                            modelContainer: modelContainer
                        )
                    )
                    .navigationTitle("Portfolio")
                }
            }

            Tab("Holdings", systemImage: "bitcoinsign.circle.fill", value: .holdings) {
                HoldingsTab(
                    apiClient: apiClient,
                    priceService: priceService,
                    fifoCalculator: fifoCalculator,
                    modelContainer: modelContainer
                )
            }

            Tab("History", systemImage: "clock.fill", value: .history) {
                NavigationStack {
                    TradeHistoryView(
                        processor: TradeHistoryProcessor(
                            modelContainer: modelContainer
                        )
                    )
                    .navigationTitle("History")
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack {
                    SettingsView(
                        processor: SettingsProcessor(
                            keychainService: keychainService,
                            apiClient: apiClient,
                            modelContainer: modelContainer
                        )
                    )
                    .navigationTitle("Settings")
                }
            }
        }
    }

    // MARK: - Onboarding

    private var onboardingView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 8) {
                    Text("Welcome to EasyCrypto")
                        .font(.title.bold())
                    Text("Add your Binance API credentials to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                SettingsView(
                    processor: SettingsProcessor(
                        keychainService: keychainService,
                        apiClient: apiClient,
                        modelContainer: modelContainer
                    )
                )

                Spacer()
            }
            .padding()
            .navigationTitle("Setup")
            .onChange(of: hasApiKey) { _, newValue in
                // Handled by re-check
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeyChanged)) { _ in
            checkApiKey()
        }
    }

    private func checkApiKey() {
        do {
            let credentials = try keychainService.load()
            hasApiKey = credentials != nil
        } catch {
            hasApiKey = false
        }
    }
}

// MARK: - Tab Enum

enum AppTab: Hashable {
    case portfolio, holdings, history, settings
}

// MARK: - Holdings Tab (with navigation to CoinDetail)

private struct HoldingsTab: View {
    let apiClient: BinanceAPIClient
    let priceService: PriceService
    let fifoCalculator: FIFOCalculator
    let modelContainer: ModelContainer

    @State private var selectedHolding: Holding?

    var body: some View {
        NavigationStack {
            HoldingsListView(
                processor: HoldingsProcessor(
                    priceService: priceService,
                    fifoCalculator: fifoCalculator,
                    modelContainer: modelContainer
                ),
                onSelectHolding: { holding in
                    selectedHolding = holding
                }
            )
            .navigationTitle("Holdings")
            .navigationDestination(item: $selectedHolding) { holding in
                CoinDetailView(
                    processor: CoinDetailProcessor(
                        apiClient: apiClient,
                        priceService: priceService,
                        fifoCalculator: fifoCalculator,
                        modelContainer: modelContainer
                    ),
                    asset: holding.asset
                )
            }
        }
    }
}

// MARK: - Notification for API key changes

extension Notification.Name {
    static let apiKeyChanged = Notification.Name("apiKeyChanged")
}

// MARK: - Previews

#Preview("Main tabs") {
    let container = PreviewSampleData.container
    ContentView(
        keychainService: KeychainService(
            save: { _, _ in }, load: { KeychainCredentials(apiKey: "k", secret: "s") }, delete: { }
        ),
        apiClient: .preview,
        tradeImportService: .preview,
        priceService: .preview,
        fifoCalculator: .live,
        modelContainer: container
    )
    .preferredColorScheme(.dark)
}

#Preview("Onboarding") {
    let container = PreviewSampleData.container
    ContentView(
        keychainService: KeychainService(
            save: { _, _ in }, load: { nil }, delete: { }
        ),
        apiClient: .noop,
        tradeImportService: .noop,
        priceService: .noop,
        fifoCalculator: .live,
        modelContainer: container
    )
    .preferredColorScheme(.dark)
}
