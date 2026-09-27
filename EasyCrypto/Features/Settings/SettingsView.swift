//
//  SettingsView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @State var processor: SettingsProcessor

    @State private var apiKeyInput = ""
    @State private var secretInput = ""

    private var state: SettingsState { processor.state }

    @State private var showRemoveKeyAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                apiKeySection
                connectionSection
                tradingModeSection
                syncStatsSection
                alertsSection
                insightsSection
                notificationLogSection
                dangerZone
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .task {
            await processor.handle(.loadCredentials)
            await processor.handle(.loadAlerts)
            await processor.handle(.loadInsightsSettings)
            await processor.handle(.loadTradingMode)
        }
        .alert("Clear All Data", isPresented: Binding(
            get: { state.showClearConfirmation },
            set: { _ in processor.state.showClearConfirmation = false }
        )) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Everything", role: .destructive) {
                processor.send(.clearAllData)
            }
        } message: {
            Text("This will delete all trades, sync data, and API keys. This action cannot be undone.")
        }
        .alert("Remove API Key?", isPresented: $showRemoveKeyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                processor.send(.deleteApiKey)
            }
        } message: {
            Text("This removes the key from Keychain. You will need to re-enter it to sync again.")
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API Credentials", systemImage: "key.fill")
                .font(.headline)

            if state.hasApiKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                    Text("API key configured")
                        .font(.subheadline)
                    Spacer()
                    Button("Remove") {
                        showRemoveKeyAlert = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.loss)
                }
            } else {
                VStack(spacing: 10) {
                    SecureField("API Key", text: $apiKeyInput)
                        .textContentType(.none)
                        .autocorrectionDisabled()

                    SecureField("Secret Key", text: $secretInput)
                        .textContentType(.none)
                        .autocorrectionDisabled()

                    Button {
                        processor.send(.saveApiKey(apiKey: apiKeyInput, secret: secretInput))
                    } label: {
                        Text("Save Credentials")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(apiKeyInput.isEmpty || secretInput.isEmpty)

                    // Inline API key creation guidance
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to create an API key:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("1. Go to binance.com → API Management")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("2. Create API key with Spot/Margin reading permissions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("3. Copy the key and secret below")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link("Open Binance API Docs →", destination: URL(string: "https://www.binance.com/en/support/faq/how-to-create-api-keys-on-binance-360002502072")!)
                            .font(.caption2)
                            .tint(Theme.accent)
                    }
                    .padding(.top, 4)

                    // Keychain security indicator
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.profit)
                        Text("Stored securely in iOS Keychain")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.loss)
            }
        }
        .glassCard()
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connection", systemImage: "network")
                .font(.headline)

            HStack {
                connectionStatusView
                Spacer()
                Button {
                    processor.send(.testConnection)
                } label: {
                    Text("Test")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(!state.hasApiKey || isConnectionTesting)
            }
        }
        .glassCard()
    }

    private var isConnectionTesting: Bool {
        if case .testing = state.connectionStatus { return true }
        return false
    }

    private var marginRiskMessage: String {
        switch state.selectedTradingMode {
        case .crossMargin:
            return "Cross Margin allows you to borrow funds to trade larger positions. " +
            "This comes with significant risks:\n\n" +
            "• Amplified losses: losses can exceed your initial deposit\n" +
            "• Liquidation risk: positions can be force-closed if margin requirements are not met\n" +
            "• Borrowing fees: interest accrues daily on borrowed funds\n" +
            "• Margin calls: Binance can require you to add funds or close positions"
        case .isolatedMargin:
            return "Isolated Margin limits borrowing to a single trading pair. " +
            "Risks include:\n\n" +
            "• Amplified losses limited to the isolated margin for that pair\n" +
            "• Liquidation risk within the isolated margin\n" +
            "• Borrowing fees: interest accrues daily\n" +
            "• Auto-repay: losses can auto-repay from your isolated margin"
        default:
            return ""
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch state.connectionStatus {
        case .idle:
            Label("Not tested", systemImage: "minus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.profit)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.loss)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Trading Mode

    private var tradingModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trading Mode", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            Picker("Trading Mode", selection: Binding(
                get: { state.selectedTradingMode },
                set: { [weak processor] newMode in
                    guard let processor else { return }
                    Task { await processor.handle(.setTradingMode(newMode)) }
                }
            )) {
                ForEach(TradingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if state.selectedTradingMode != .spot, !marginRiskMessage.isEmpty {
                Text(marginRiskMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
        .glassCard()
    }

    // MARK: - Sync Stats

    private var syncStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sync Stats", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                MetricCard(
                    label: "Total Trades",
                    value: "\(state.tradeCount)"
                )
                MetricCard(
                    label: "Synced Symbols",
                    value: "\(state.syncedSymbolCount)"
                )
            }
        }
        .glassCard()
    }

    // MARK: - AI Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Insights", systemImage: "sparkles")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { state.aiInsightsEnabled },
                set: { processor.send(.setInsightsEnabled($0)) }
            )) {
                Text("On-device insights")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Theme.accent)

            Text("Insights are generated on your device using on-device AI and never leave your iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    // MARK: - Price Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Price Alerts", systemImage: "bell.fill")
                .font(.headline)

            if !state.notificationsAuthorized {
                Button {
                    processor.send(.requestNotificationPermission)
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }

            if state.alertRows.isEmpty {
                Text("Sync trades to configure per-coin profit alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.alertRows) { row in
                    alertRowView(row)
                }
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func alertRowView(_ row: PriceAlertRow) -> some View {
        VStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { row.isEnabled },
                set: { processor.send(.setAlertEnabled(symbol: row.symbol, enabled: $0)) }
            )) {
                Text(row.asset)
                    .font(.subheadline.weight(.medium))
            }
            .tint(Theme.accent)

            if row.isEnabled {
                HStack {
                    Text("Notify on profit increase of")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("100", value: Binding(
                        get: { row.thresholdUSD },
                        set: { processor.send(.setAlertThreshold(symbol: row.symbol, threshold: $0)) }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    Text("USDT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Notify on price move of")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("5", value: Binding(
                        get: { row.percentThreshold },
                        set: { processor.send(.setAlertPercent(symbol: row.symbol, percent: $0)) }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Notification Log

    private var notificationLogSection: some View {
        NavigationLink {
            NotificationLogView(processor: processor)
        } label: {
            HStack {
                Label("Notification Log", systemImage: "bell.badge.fill")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.loss)

            Button(role: .destructive) {
                processor.state.showClearConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Clear All Data")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.loss)

            if state.dataCleared {
                Label("All data cleared successfully", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.profit)
            }
        }
        .glassCard()
    }
}

// MARK: - Previews

#Preview("No API key (onboarding)") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = SettingsProcessor(
        keychainService: KeychainService(
            save: { _, _ in }, load: { nil }, delete: { }
        ),
        apiClient: .noop,
        modelContainer: container
    )
    return NavigationStack {
        SettingsView(processor: processor)
            .navigationTitle("Settings")
    }
    .preferredColorScheme(.dark)
}

#Preview("API key saved") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = SettingsProcessor(
        keychainService: KeychainService(
            save: { _, _ in },
            load: { KeychainCredentials(apiKey: "key", secret: "secret") },
            delete: { }
        ),
        apiClient: .noop,
        modelContainer: container
    )
    processor.state.hasApiKey = true
    processor.state.tradeCount = 247
    processor.state.syncedSymbolCount = 5
    return NavigationStack {
        SettingsView(processor: processor)
            .navigationTitle("Settings")
    }
    .preferredColorScheme(.dark)
}

#Preview("Connection test result") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = SettingsProcessor(
        keychainService: KeychainService(
            save: { _, _ in },
            load: { KeychainCredentials(apiKey: "key", secret: "secret") },
            delete: { }
        ),
        apiClient: .noop,
        modelContainer: container
    )
    processor.state.hasApiKey = true
    processor.state.connectionStatus = .success
    processor.state.tradeCount = 247
    processor.state.syncedSymbolCount = 5
    return NavigationStack {
        SettingsView(processor: processor)
            .navigationTitle("Settings")
    }
    .preferredColorScheme(.dark)
}
