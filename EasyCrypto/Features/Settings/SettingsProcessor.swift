//
//  SettingsProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class SettingsProcessor: Processor {
    var state = SettingsState()

    private let keychainService: KeychainService
    private let apiClient: BinanceAPIClient
    private let notificationService: NotificationService
    private let insightSettings: InsightSettingsStore
    private let modelContext: ModelContext

    init(
        keychainService: KeychainService,
        apiClient: BinanceAPIClient,
        modelContainer: ModelContainer,
        notificationService: NotificationService = .live,
        insightSettings: InsightSettingsStore = .live()
    ) {
        self.keychainService = keychainService
        self.apiClient = apiClient
        self.notificationService = notificationService
        self.insightSettings = insightSettings
        self.modelContext = ModelContext(modelContainer)
    }

    func handle(_ intent: SettingsIntent) async {
        switch intent {
        case .saveApiKey(let apiKey, let secret):
            await saveApiKey(apiKey: apiKey, secret: secret)
        case .deleteApiKey:
            await deleteApiKey()
        case .testConnection:
            await testConnection()
        case .clearAllData:
            await clearAllData()
        case .loadCredentials:
            await loadCredentials()
        case .loadAlerts:
            await loadAlerts()
        case .loadNotificationLog:
            await loadNotificationLog()
        case .requestNotificationPermission:
            await requestNotificationPermission()
        case .setAlertEnabled(let symbol, let enabled):
            await setAlertEnabled(symbol: symbol, enabled: enabled)
        case .setAlertThreshold(let symbol, let threshold):
            await setAlertThreshold(symbol: symbol, threshold: threshold)
        case .setAlertPercent(let symbol, let percent):
            await setAlertPercent(symbol: symbol, percent: percent)
        case .loadInsightsSettings:
            state.aiInsightsEnabled = insightSettings.isEnabled()
        case .setInsightsEnabled(let enabled):
            insightSettings.setEnabled(enabled)
            state.aiInsightsEnabled = enabled
        }
    }

    private func loadCredentials() async {
        do {
            let credentials = try keychainService.load()
            state.hasApiKey = credentials != nil
            try updateStats()
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func saveApiKey(apiKey: String, secret: String) async {
        state.isLoading = true
        state.error = nil

        do {
            try keychainService.save(apiKey, secret)
            state.hasApiKey = true
            NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    private func deleteApiKey() async {
        state.error = nil

        do {
            try keychainService.delete()
            state.hasApiKey = false
            state.connectionStatus = .idle
            NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func testConnection() async {
        state.connectionStatus = .testing

        do {
            let balances = try await apiClient.fetchAccount()
            let count = balances.count
            state.connectionStatus = .success
            _ = count // Connection verified
        } catch {
            state.connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func clearAllData() async {
        state.isLoading = true
        state.error = nil

        do {
            try modelContext.delete(model: Trade.self)
            try modelContext.delete(model: SyncMetadata.self)
            try modelContext.save()
            try keychainService.delete()
            state.hasApiKey = false
            state.connectionStatus = .idle
            state.tradeCount = 0
            state.syncedSymbolCount = 0
            state.dataCleared = true
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    private func updateStats() throws {
        let tradeDescriptor = FetchDescriptor<Trade>()
        state.tradeCount = try modelContext.fetchCount(tradeDescriptor)

        let syncDescriptor = FetchDescriptor<SyncMetadata>()
        state.syncedSymbolCount = try modelContext.fetchCount(syncDescriptor)
    }

    // MARK: - Price Alerts

    private func loadAlerts() async {
        state.notificationsAuthorized = await notificationService.isAuthorized()
        do {
            let trades = try modelContext.fetch(FetchDescriptor<Trade>())
            let assets = Set(trades.map { $0.asset }).sorted()
            let configs = try modelContext.fetch(FetchDescriptor<PriceAlertConfig>())
            let configBySymbol = Dictionary(
                configs.map { ($0.symbol, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            state.alertRows = assets.map { asset in
                let symbol = "\(asset)USDT"
                let existing = configBySymbol[symbol]
                return PriceAlertRow(
                    symbol: symbol,
                    asset: asset,
                    isEnabled: existing?.isEnabled ?? false,
                    thresholdUSD: existing?.thresholdUSD ?? 100,
                    percentThreshold: existing?.percentThreshold ?? 5
                )
            }
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func requestNotificationPermission() async {
        state.notificationsAuthorized = await notificationService.requestAuthorization()
    }

    private func loadNotificationLog() async {
        do {
            let entries = try modelContext.fetch(
                FetchDescriptor<NotificationLogEntry>(
                    sortBy: [SortDescriptor(\.firedAt, order: .reverse)]
                )
            )
            state.notificationLog = entries.map { entry in
                NotificationLogRow(
                    id: entry.id,
                    symbol: entry.symbol,
                    asset: entry.asset,
                    title: entry.title,
                    body: entry.body,
                    direction: entry.direction,
                    value: entry.value,
                    firedAt: entry.firedAt
                )
            }
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func setAlertEnabled(symbol: String, enabled: Bool) async {
        do {
            let config = try upsertConfig(symbol: symbol)
            config.isEnabled = enabled
            try modelContext.save()
            updateRow(symbol: symbol) { $0.isEnabled = enabled }
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func setAlertThreshold(symbol: String, threshold: Double) async {
        do {
            let config = try upsertConfig(symbol: symbol)
            config.thresholdUSD = threshold
            try modelContext.save()
            updateRow(symbol: symbol) { $0.thresholdUSD = threshold }
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func setAlertPercent(symbol: String, percent: Double) async {
        do {
            let config = try upsertConfig(symbol: symbol)
            config.percentThreshold = percent
            try modelContext.save()
            updateRow(symbol: symbol) { $0.percentThreshold = percent }
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func upsertConfig(symbol: String) throws -> PriceAlertConfig {
        let target = symbol
        let descriptor = FetchDescriptor<PriceAlertConfig>(
            predicate: #Predicate { $0.symbol == target }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let config = PriceAlertConfig(symbol: symbol)
        modelContext.insert(config)
        return config
    }

    private func updateRow(symbol: String, _ mutate: (inout PriceAlertRow) -> Void) {
        guard let index = state.alertRows.firstIndex(where: { $0.symbol == symbol }) else { return }
        var row = state.alertRows[index]
        mutate(&row)
        state.alertRows[index] = row
    }
}
