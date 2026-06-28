//
//  SettingsInsightsTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given a SettingsProcessor managing the AI insights toggle")
@MainActor
struct SettingsInsightsTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self, NotificationLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeProcessor(
        container: ModelContainer,
        settings: InsightSettingsStore
    ) -> SettingsProcessor {
        SettingsProcessor(
            keychainService: KeychainService(save: { _, _ in }, load: { nil }, delete: { }),
            apiClient: .noop,
            modelContainer: container,
            notificationService: .preview,
            insightSettings: settings
        )
    }

    @Test("When toggled off then loaded, the disabled state round-trips through the store")
    func toggleRoundTrips() async throws {
        let container = try makeContainer()
        let defaults = UserDefaults(suiteName: "test-settings-insights-\(UUID().uuidString)")!
        let store = InsightSettingsStore.live(defaults: defaults)
        let processor = makeProcessor(container: container, settings: store)

        // Defaults to enabled.
        await processor.handle(.loadInsightsSettings)
        #expect(processor.state.aiInsightsEnabled == true)

        // Turn it off — persists to the store.
        await processor.handle(.setInsightsEnabled(false))
        #expect(processor.state.aiInsightsEnabled == false)
        #expect(store.isEnabled() == false)

        // A fresh processor reads the persisted value.
        let reloaded = makeProcessor(container: container, settings: store)
        await reloaded.handle(.loadInsightsSettings)
        #expect(reloaded.state.aiInsightsEnabled == false)
    }
}
