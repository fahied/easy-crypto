//
//  CandleAlertService.swift
//  EasyCrypto
//

import Foundation
import os

// MARK: - Drop Rule

/// Pure rule for detecting a falling price across recent candles.
nonisolated enum CandleDrop {
    /// `true` when the last two closed candles each closed lower than the candle
    /// immediately before them (two consecutive lower closes).
    ///
    /// Requires at least three candles; only the most recent three closes are used.
    /// Note: this measures consecutive *lower closes*, not bearish (`close < open`)
    /// candles — see ADV-CORE-SERVICES-004 "Design Decision".
    static func isConsecutiveDrop(_ closed: [Kline]) -> Bool {
        guard closed.count >= 3 else { return false }
        let last3 = Array(closed.suffix(3))
        return last3[1].close < last3[0].close && last3[2].close < last3[1].close
    }
}

// MARK: - Types

/// One asset's candle-drop alert configuration.
nonisolated struct CandleAlertInput: Sendable, Equatable {
    let symbol: String          // e.g. "BTCUSDT"
    let asset: String           // e.g. "BTC"
    let isEnabled: Bool
    /// `openTime` of the latest candle that previously triggered a drop alert.
    let lastCandleDropOpenTime: Int64
}

// MARK: - Service (struct-with-closures pattern)

nonisolated struct CandleAlertService: Sendable {
    /// Fetches the last closed 15m candles for each enabled config, fires a local
    /// notification when the last two candles consecutively closed lower, and
    /// returns the fired alerts. `newBaseline` carries the latest candle's
    /// `openTime` (as a `Double`) so the caller can persist per-coin de-dup.
    var evaluate: @Sendable (_ configs: [CandleAlertInput]) async throws -> [FiredAlert]
}

// MARK: - Live Implementation

extension CandleAlertService {
    /// Interval and fetch limit: 5 candles so that after dropping the in-progress
    /// candle at least 4 closed candles remain (3 are needed to evaluate the rule).
    nonisolated static let interval = "15m"
    nonisolated static let fetchLimit = 5

    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "candle-alerts"
    )

    static func live(
        fetchKlines: @escaping @Sendable (_ symbol: String, _ interval: String, _ limit: Int) async throws -> [Kline],
        notificationService: NotificationService,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> CandleAlertService {
        CandleAlertService(
            evaluate: { configs in
                let enabled = configs.filter(\.isEnabled)
                guard !enabled.isEmpty else { return [] }

                var fired: [FiredAlert] = []
                for config in enabled {
                    let klines = try await fetchKlines(config.symbol, interval, fetchLimit)
                    let closed = closedCandles(klines, now: now())
                    guard CandleDrop.isConsecutiveDrop(closed), let latest = closed.last else {
                        continue
                    }
                    // De-dup: only fire once per latest candle.
                    guard latest.openTime != config.lastCandleDropOpenTime else { continue }

                    let alert = LocalAlert(
                        id: "candle-drop-\(config.symbol)",
                        title: "\(config.asset) dropping",
                        body: "2 consecutive 15m candles down — \(config.asset) now \(Int(latest.close.rounded())) USDT."
                    )
                    await notificationService.scheduleAlert(alert)
                    fired.append(FiredAlert(
                        symbol: config.symbol,
                        asset: config.asset,
                        direction: .candleDrop,
                        currentProfit: latest.close,
                        newBaseline: Double(latest.openTime),
                        deliveredAlert: alert
                    ))
                }

                logger.info("Candle-drop evaluation fired \(fired.count) alert(s)")
                return fired
            }
        )
    }

    /// Keeps only candles that have already closed (drops the in-progress one).
    nonisolated private static func closedCandles(_ klines: [Kline], now: Date) -> [Kline] {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        return klines.filter { $0.closeTime <= nowMs }
    }

    static let noop = CandleAlertService(evaluate: { _ in [] })
}
