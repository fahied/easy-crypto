//
//  SettingsProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
}

private func makeProcessor(
    container: ModelContainer,
    savedCredentials: KeychainCredentials? = nil,
    fetchAccountResult: @escaping @Sendable () async throws -> [BinanceBalance] = { [] }
) -> SettingsProcessor {
    var storedCredentials = savedCredentials
    return SettingsProcessor(
        keychainService: KeychainService(
            save: { apiKey, secret in
                storedCredentials = KeychainCredentials(apiKey: apiKey, secret: secret)
            },
            load: { storedCredentials },
            delete: { storedCredentials = nil }
        ),
        apiClient: BinanceAPIClient(
            fetchAccount: fetchAccountResult,
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        ),
        modelContainer: container
    )
}

// MARK: - Initial State

@Suite("Given a SettingsProcessor with initial state")
struct SettingsInitTests {

    @Test("Then state has empty defaults")
    func initialState() throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)
        #expect(processor.state.hasApiKey == false)
        #expect(processor.state.tradeCount == 0)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }
}

// MARK: - Load Credentials

@Suite("Given a SettingsProcessor loading credentials")
struct SettingsLoadTests {

    @Test("When credentials exist in keychain, then hasApiKey is true")
    func existingCredentials() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(
            container: container,
            savedCredentials: KeychainCredentials(apiKey: "key", secret: "secret")
        )

        await processor.handle(.loadCredentials)

        #expect(processor.state.hasApiKey == true)
    }

    @Test("When no credentials exist, then hasApiKey is false")
    func noCredentials() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.loadCredentials)

        #expect(processor.state.hasApiKey == false)
    }
}

// MARK: - Save API Key

@Suite("Given a SettingsProcessor saving API keys")
struct SettingsSaveTests {

    @Test("When saving valid credentials, then hasApiKey becomes true")
    func savesKey() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.saveApiKey(apiKey: "my-key", secret: "my-secret"))

        #expect(processor.state.hasApiKey == true)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }

    @Test("When save fails, then error is set")
    func saveError() async throws {
        let container = try makeContainer()
        let processor = SettingsProcessor(
            keychainService: KeychainService(
                save: { _, _ in throw KeychainError.saveFailed(status: -1) },
                load: { nil },
                delete: { }
            ),
            apiClient: .noop,
            modelContainer: container
        )

        await processor.handle(.saveApiKey(apiKey: "key", secret: "secret"))

        #expect(processor.state.error != nil)
        #expect(processor.state.hasApiKey == false)
    }
}

// MARK: - Delete API Key

@Suite("Given a SettingsProcessor deleting API keys")
struct SettingsDeleteTests {

    @Test("When deleting credentials, then hasApiKey becomes false")
    func deletesKey() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(
            container: container,
            savedCredentials: KeychainCredentials(apiKey: "key", secret: "secret")
        )

        await processor.handle(.loadCredentials)
        #expect(processor.state.hasApiKey == true)

        await processor.handle(.deleteApiKey)

        #expect(processor.state.hasApiKey == false)
    }
}

// MARK: - Test Connection

@Suite("Given a SettingsProcessor testing connection")
struct SettingsConnectionTests {

    @Test("When connection succeeds, then status is .success")
    func connectionSuccess() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(
            container: container,
            fetchAccountResult: {
                [BinanceBalance(asset: "BTC", free: "0.5", locked: "0")]
            }
        )

        await processor.handle(.testConnection)

        if case .success = processor.state.connectionStatus {
            // expected
        } else {
            Issue.record("Expected .success but got \(processor.state.connectionStatus)")
        }
    }

    @Test("When connection fails, then status is .failed with message")
    func connectionFailed() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(
            container: container,
            fetchAccountResult: {
                throw BinanceError.invalidCredentials
            }
        )

        await processor.handle(.testConnection)

        if case .failed(let message) = processor.state.connectionStatus {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected .failed but got \(processor.state.connectionStatus)")
        }
    }
}

// MARK: - Clear All Data

@Suite("Given a SettingsProcessor clearing data")
struct SettingsClearTests {

    @Test("When clearing all data, then trades and sync metadata are deleted")
    func clearsData() async throws {
        let container = try makeContainer()
        // Seed some data
        let context = ModelContext(container)
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(), isBuyer: true, orderId: 100
        ))
        context.insert(SyncMetadata(symbol: "BTCUSDT", lastTradeId: 1, lastSyncDate: Date()))
        try context.save()

        let processor = makeProcessor(container: container)

        await processor.handle(.clearAllData)

        #expect(processor.state.tradeCount == 0)
        #expect(processor.state.syncedSymbolCount == 0)
        #expect(processor.state.hasApiKey == false)
        #expect(processor.state.dataCleared == true)
    }

    @Test("When clearing data, then connection status resets to idle")
    func resetsConnectionStatus() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.clearAllData)

        if case .idle = processor.state.connectionStatus {
            // expected
        } else {
            Issue.record("Expected .idle")
        }
    }
}

// MARK: - Trading Mode

@Suite("Given a SettingsProcessor with trading mode", .serialized)
struct SettingsTradingModeTests {

    @Test("When setting trading mode, then state is updated")
    func setsTradingMode() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.setTradingMode(.crossMargin))

        #expect(processor.state.selectedTradingMode == .crossMargin)
    }

    @Test("When setting cross-margin, then UserDefaults is persisted")
    func persistsCrossMargin() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.setTradingMode(.crossMargin))

        #expect(UserDefaults.standard.string(forKey: "selectedTradingMode") == "cross_margin")
    }

    @Test("When setting isolated-margin, then UserDefaults is persisted")
    func persistsIsolatedMargin() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.setTradingMode(.isolatedMargin))

        #expect(UserDefaults.standard.string(forKey: "selectedTradingMode") == "isolated_margin")
    }

    @Test("When switching back to spot, then mode resets")
    func resetsToSpot() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container)

        await processor.handle(.setTradingMode(.crossMargin))
        await processor.handle(.setTradingMode(.spot))

        #expect(processor.state.selectedTradingMode == .spot)
        #expect(UserDefaults.standard.string(forKey: "selectedTradingMode") == "spot")
    }

    @Test("When loading trading mode, then state reads from UserDefaults")
    func loadsFromUserDefaults() async throws {
        let container = try makeContainer()
        UserDefaults.standard.set("isolated_margin", forKey: "selectedTradingMode")

        let processor = makeProcessor(container: container)

        await processor.handle(.loadTradingMode)

        #expect(processor.state.selectedTradingMode == .isolatedMargin)
    }

    @Test("When no trading mode stored, then defaults to spot")
    func defaultsToSpot() async throws {
        let container = try makeContainer()
        UserDefaults.standard.removeObject(forKey: "selectedTradingMode")

        let processor = makeProcessor(container: container)

        await processor.handle(.loadTradingMode)

        #expect(processor.state.selectedTradingMode == .spot)
    }
}
