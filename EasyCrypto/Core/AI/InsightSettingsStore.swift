//
//  InsightSettingsStore.swift
//  EasyCrypto
//

import Foundation

/// Persisted on/off switch for the on-device AI insights feature.
///
/// Backed by `UserDefaults` so it can be read synchronously from both the Insights
/// surface and the background refresher (ADV-AI-INSIGHTS-004). Defaults to enabled.
nonisolated struct InsightSettingsStore: Sendable {
    var isEnabled: @Sendable () -> Bool
    var setEnabled: @Sendable (Bool) -> Void
}

extension InsightSettingsStore {
    static let key = "ai_insights_enabled"

    static func live(defaults: UserDefaults = .standard) -> InsightSettingsStore {
        InsightSettingsStore(
            isEnabled: { (defaults.object(forKey: key) as? Bool) ?? true },
            setEnabled: { defaults.set($0, forKey: key) }
        )
    }
}
