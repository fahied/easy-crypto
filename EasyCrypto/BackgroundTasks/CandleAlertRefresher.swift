//
//  CandleAlertRefresher.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Bridges persisted alert state to `CandleAlertService` for the hourly
/// candle-drop check.
///
/// Throttles to at most once per hour via `CandleAlertState.lastCheckedAt`,
/// evaluates enabled configs, persists the per-coin de-dup baseline, and writes a
/// `NotificationLogEntry` for each delivered alert — all in one save transaction.
enum CandleAlertRefresher {
    /// Minimum spacing between candle-drop checks (approximates an hourly cadence).
    static let throttleInterval: TimeInterval = 60 * 60

    @MainActor
    static func run(
        modelContext: ModelContext,
        candleService: CandleAlertService,
        now: Date = Date()
    ) async throws {
        let states = try modelContext.fetch(FetchDescriptor<CandleAlertState>())
        let state: CandleAlertState
        if let existing = states.first {
            state = existing
        } else {
            state = CandleAlertState()
            modelContext.insert(state)
        }

        // Hourly throttle: skip if checked within the last hour.
        guard now.timeIntervalSince(state.lastCheckedAt) >= throttleInterval else { return }

        let enabledPredicate = #Predicate<PriceAlertConfig> { $0.isEnabled }
        let configs = try modelContext.fetch(
            FetchDescriptor<PriceAlertConfig>(predicate: enabledPredicate)
        )

        let inputs: [CandleAlertInput] = configs.map { config in
            let asset = config.symbol.hasSuffix("USDT")
                ? String(config.symbol.dropLast(4))
                : config.symbol
            return CandleAlertInput(
                symbol: config.symbol,
                asset: asset,
                isEnabled: config.isEnabled,
                lastCandleDropOpenTime: config.lastCandleDropOpenTime
            )
        }

        let fired = try await candleService.evaluate(inputs)

        let configBySymbol = Dictionary(
            configs.map { ($0.symbol, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for alert in fired {
            if let config = configBySymbol[alert.symbol] {
                config.lastCandleDropOpenTime = Int64(alert.newBaseline)
            }
            if let delivered = alert.deliveredAlert {
                modelContext.insert(NotificationLogEntry(
                    symbol: alert.symbol,
                    asset: alert.asset,
                    title: delivered.title,
                    body: delivered.body,
                    direction: "candleDrop",
                    value: alert.currentProfit,
                    firedAt: now
                ))
            }
        }

        state.lastCheckedAt = now
        try modelContext.save()
    }
}
