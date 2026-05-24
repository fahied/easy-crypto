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
    private let modelContext: ModelContext

    init(
        keychainService: KeychainService,
        apiClient: BinanceAPIClient,
        modelContainer: ModelContainer
    ) {
        self.keychainService = keychainService
        self.apiClient = apiClient
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
}
