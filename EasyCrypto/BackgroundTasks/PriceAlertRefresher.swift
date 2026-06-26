//
//  PriceAlertRefresher.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Bridges persisted alert state to `PriceAlertService` for background evaluation.
///
/// Loads enabled `PriceAlertConfig` rows and their trades, evaluates alerts, and
/// persists the advanced baselines for any alert that fired. Kept separate from
/// the BGTaskScheduler glue so the data-flow can be unit tested.
enum PriceAlertRefresher {
    /// Identifier registered for the background app-refresh task.
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.fahied.EasyCrypto.priceAlertRefresh"

    @MainActor
    static func run(modelContext: ModelContext, alertService: PriceAlertService) async throws {
        let enabledPredicate = #Predicate<PriceAlertConfig> { $0.isEnabled }
        let configs = try modelContext.fetch(
            FetchDescriptor<PriceAlertConfig>(predicate: enabledPredicate)
        )
        guard !configs.isEmpty else { return }

        let allTrades = try modelContext.fetch(
            FetchDescriptor<Trade>(sortBy: [SortDescriptor(\.timestamp)])
        )
        let tradesByAsset = Dictionary(grouping: allTrades) { $0.asset }

        let inputs: [PriceAlertConfigInput] = configs.map { config in
            let asset = config.symbol.hasSuffix("USDT")
                ? String(config.symbol.dropLast(4))
                : config.symbol
            let fifoTrades = (tradesByAsset[asset] ?? []).map {
                FIFOTrade(
                    price: $0.price,
                    quantity: $0.quantity,
                    commission: $0.commission,
                    commissionAsset: $0.commissionAsset,
                    asset: $0.asset,
                    isBuyer: $0.isBuyer
                )
            }
            return PriceAlertConfigInput(
                symbol: config.symbol,
                asset: asset,
                isEnabled: config.isEnabled,
                thresholdUSD: config.thresholdUSD,
                lastNotifiedProfit: config.lastNotifiedProfit,
                lastNotifiedLoss: config.lastNotifiedLoss,
                trades: fifoTrades
            )
        }

        let fired = try await alertService.evaluate(inputs)
        guard !fired.isEmpty else { return }

        let configBySymbol = Dictionary(
            configs.map { ($0.symbol, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for alert in fired {
            guard let config = configBySymbol[alert.symbol] else { continue }
            switch alert.direction {
            case .gain:
                config.lastNotifiedProfit = alert.newBaseline
            case .loss:
                config.lastNotifiedLoss = alert.newBaseline
            }
        }
        try modelContext.save()
    }
}
