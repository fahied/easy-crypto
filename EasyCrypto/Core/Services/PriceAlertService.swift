//
//  PriceAlertService.swift
//  EasyCrypto
//

import Foundation
import os

// MARK: - Types

/// Direction of a fired alert, so the caller knows which baseline to advance.
nonisolated enum AlertDirection: Sendable, Equatable {
    case gain
    case loss
}

/// One asset's alert configuration plus the trades needed to value it.
nonisolated struct PriceAlertConfigInput: Sendable, Equatable {
    let symbol: String          // e.g. "BTCUSDT"
    let asset: String           // e.g. "BTC"
    let isEnabled: Bool
    let thresholdUSD: Double
    let lastNotifiedProfit: Double
    let lastNotifiedLoss: Double
    let trades: [FIFOTrade]
}

/// An alert that fired, with the advanced baseline the caller should persist into
/// the field matching `direction`.
nonisolated struct FiredAlert: Sendable, Equatable {
    let symbol: String
    let asset: String
    let direction: AlertDirection
    let currentProfit: Double
    let newBaseline: Double
}

// MARK: - Service (struct-with-closures pattern)

nonisolated struct PriceAlertService: Sendable {
    /// Evaluates the given alert configs against current prices, delivers a local
    /// notification for each alert that fires, and returns the fired alerts with the
    /// advanced baseline (`newBaseline`) the caller should persist.
    ///
    /// A gain alert fires when `currentProfit - lastNotifiedProfit >= thresholdUSD`;
    /// a loss alert fires when `lastNotifiedLoss - currentProfit >= thresholdUSD`.
    /// Each baseline advances to the current profit so the next alert in that
    /// direction requires a further `thresholdUSD` move.
    var evaluate: @Sendable (_ configs: [PriceAlertConfigInput]) async throws -> [FiredAlert]
}

// MARK: - Live Implementation

extension PriceAlertService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "alerts"
    )

    static func live(
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        notificationService: NotificationService
    ) -> PriceAlertService {
        PriceAlertService(
            evaluate: { configs in
                let enabled = configs.filter(\.isEnabled)
                guard !enabled.isEmpty else { return [] }

                let symbols = Array(Set(enabled.map(\.symbol)))
                let prices = try await priceService.fetchPrices(symbols)

                var fired: [FiredAlert] = []
                for config in enabled {
                    guard let price = prices[config.symbol] else { continue }

                    let profit = UnrealizedProfit.compute(
                        trades: config.trades,
                        currentPrice: price,
                        using: fifoCalculator
                    )

                    if profit - config.lastNotifiedProfit >= config.thresholdUSD {
                        await notificationService.scheduleAlert(LocalAlert(
                            id: "price-alert-gain-\(config.symbol)",
                            title: "\(config.asset) profit up",
                            body: "\(config.asset) unrealized P&L is now \(Int(profit.rounded())) USDT."
                        ))
                        fired.append(FiredAlert(
                            symbol: config.symbol,
                            asset: config.asset,
                            direction: .gain,
                            currentProfit: profit,
                            newBaseline: profit
                        ))
                    }

                    if config.lastNotifiedLoss - profit >= config.thresholdUSD {
                        await notificationService.scheduleAlert(LocalAlert(
                            id: "price-alert-loss-\(config.symbol)",
                            title: "\(config.asset) profit down",
                            body: "\(config.asset) unrealized P&L is now \(Int(profit.rounded())) USDT."
                        ))
                        fired.append(FiredAlert(
                            symbol: config.symbol,
                            asset: config.asset,
                            direction: .loss,
                            currentProfit: profit,
                            newBaseline: profit
                        ))
                    }
                }

                logger.info("Price alert evaluation fired \(fired.count) alert(s)")
                return fired
            }
        )
    }

    static let noop = PriceAlertService(evaluate: { _ in [] })
}
