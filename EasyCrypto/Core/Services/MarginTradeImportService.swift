//
//  MarginTradeImportService.swift
//  EasyCrypto
//
//  ADV-CORE-SERVICES-006: Margin trade import service for cross-margin and
//  isolated-margin incremental sync. Mirrors TradeImportService but calls
//  Binance's margin REST endpoints (/sapi/v1/margin/myTrades).

import Foundation
import os

// MARK: - Service (struct-with-closures pattern)

nonisolated struct MarginTradeImportService: Sendable {
    /// Performs margin trade sync for the given trading mode.
    ///
    /// - Parameters:
    ///   - mode: `.crossMargin` or `.isolatedMargin` — selects the margin endpoint
    ///     and determines how `existingSync` keys are interpreted.
    ///   - existingSync: Key map for incremental sync.
    ///     - Cross-margin: a single `"cross"` key → global lastTradeId.
    ///     - Isolated-margin: isolated margin key (the symbol, e.g. `"BTCUSDT"`)
    ///       → per-symbol lastTradeId.
    ///
    /// - Returns: `TradeImportResult` with mapped trades and sync metadata updates.
    var sync: @Sendable (_ mode: TradingMode, _ existingSync: [String: Int64]) async throws -> TradeImportResult
}

// MARK: - Live Implementation

extension MarginTradeImportService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "sync"
    )

    nonisolated private static let bootstrapTrackedAssets: [String] = []

    /// Delay between per-asset fetch requests to stay within Binance's weight limits.
    nonisolated private static let interRequestDelay: Duration = .milliseconds(300)

    /// Maximum retries per symbol when a 429 rate-limit response is received.
    nonisolated private static let maxRateLimitRetries = 3

    static func live(apiClient: BinanceAPIClient) -> MarginTradeImportService {
        MarginTradeImportService(
            sync: { mode, existingSync in
                switch mode {
                case .crossMargin:
                    return try await syncCrossMargin(
                        apiClient: apiClient,
                        existingSync: existingSync
                    )
                case .isolatedMargin:
                    return try await syncIsolatedMargin(
                        apiClient: apiClient,
                        existingSync: existingSync
                    )
                case .spot:
                    throw BinanceError.invalidMode(mode.rawValue)
                }
            }
        )
    }

    // MARK: - Cross-Margin Sync

    /// Cross-margin uses a single "cross" sync cursor across all symbols.
    private static func syncCrossMargin(
        apiClient: BinanceAPIClient,
        existingSync: [String: Int64]
    ) async throws -> TradeImportResult {
        let crossFromId = existingSync["cross"]

        let account = try await apiClient.fetchMarginAccount()
        let balanceAssets = (account.userAssets ?? [])
            .compactMap(\.asset)
            .filter { $0 != "USDT" }
        let previouslySyncedAssets = existingSync.keys
            .filter { $0.hasSuffix("USDT") }
            .map { String($0.dropLast(4)) }
        let assets = Array(
            Set(balanceAssets + previouslySyncedAssets + bootstrapTrackedAssets)
        )
        .filter { PriceCatalog.symbols.contains($0) }
        .sorted()

        guard !assets.isEmpty else {
            logger.info("No non-USDT assets found for cross-margin sync")
            return .empty
        }

        logger.info("Cross-margin: discovered \(assets.count) assets")

        var allTrades: [MappedTrade] = []
        var allSyncUpdates: [SyncUpdate] = []

        for (index, asset) in assets.enumerated() {
            let symbol = "\(asset)USDT"
            let startFromId = crossFromId.map { $0 + 1 }

            do {
                let assetTrades = try await fetchMarginTradesWithRetry(
                    apiClient: apiClient,
                    symbol: symbol,
                    fromId: startFromId,
                    isIsolated: false
                )

                let mapped = assetTrades.map { trade in
                    MappedTrade(
                        binanceTradeId: trade.id,
                        symbol: trade.symbol,
                        asset: asset,
                        price: Double(trade.price) ?? 0,
                        quantity: Double(trade.qty) ?? 0,
                        quoteQuantity: Double(trade.quoteQty) ?? 0,
                        commission: Double(trade.commission) ?? 0,
                        commissionAsset: trade.commissionAsset,
                        timestamp: Date(timeIntervalSince1970: Double(trade.time) / 1000),
                        isBuyer: trade.isBuyer,
                        orderId: trade.orderId
                    )
                }
                allTrades.append(contentsOf: mapped)

                if let lastTrade = assetTrades.last {
                    allSyncUpdates.append(SyncUpdate(
                        symbol: "cross",
                        lastTradeId: lastTrade.id,
                        syncDate: Date()
                    ))
                }

                logger.info("Cross-margin: fetched \(assetTrades.count) trades for \(symbol)")
            } catch {
                logger.error("Cross-margin: failed to fetch trades for \(symbol): \(error)")
                continue
            }

            if index < assets.count - 1 {
                try? await Task.sleep(for: interRequestDelay)
            }
        }

        return TradeImportResult(
            mappedTrades: allTrades,
            syncUpdates: allSyncUpdates
        )
    }

    // MARK: - Isolated-Margin Sync

    /// Isolated-margin uses per-symbol sync cursors keyed by the isolated margin key.
    private static func syncIsolatedMargin(
        apiClient: BinanceAPIClient,
        existingSync: [String: Int64]
    ) async throws -> TradeImportResult {
        // Isolated-margin positions live under `/sapi/v1/margin/isolated/account`,
        // each entry keyed by its own trading-pair `symbol` (e.g. "DEXEUSDT") with
        // a `baseAsset`/`quoteAsset` pair. `/sapi/v1/margin/allAssets` returns
        // Binance-wide asset metadata (not the user's isolated positions), so it
        // can never surface a symbol the account actually holds — that was the
        // bug: newly opened isolated pairs (e.g. DEXEUSDT) were never discovered.
        let isolatedAccount = try await apiClient.fetchIsolatedMarginAccount([])
        let balanceEntries = isolatedAccount.assets.map { pair in
            (symbol: pair.symbol, asset: pair.baseAsset.asset)
        }
        let previouslySyncedSymbols = existingSync.keys
            .filter { $0.hasSuffix("USDT") }
        let symbolToAsset = Dictionary(
            balanceEntries.map { ($0.symbol, $0.asset) },
            uniquingKeysWith: { first, _ in first }
        )
        let symbols = Array(
            Set(balanceEntries.map(\.symbol) + previouslySyncedSymbols)
        ).sorted()

        guard !symbols.isEmpty else {
            logger.info("No isolated-margin symbols found for sync")
            return .empty
        }

        logger.info("Isolated-margin: discovered \(symbols.count) symbols")

        var allTrades: [MappedTrade] = []
        var allSyncUpdates: [SyncUpdate] = []

        for (index, symbol) in symbols.enumerated() {
            // Fall back to stripping "USDT" for symbols only known from a
            // previous sync cursor (no live position, so no baseAsset from
            // the isolated account response).
            let asset = symbolToAsset[symbol] ?? String(symbol.dropLast(4))
            let lastTradeId = existingSync[symbol]
            let startFromId = lastTradeId.map { $0 + 1 }


            do {
                let assetTrades = try await fetchMarginTradesWithRetry(
                    apiClient: apiClient,
                    symbol: symbol,
                    fromId: startFromId,
                    isIsolated: true
                )

                let mapped = assetTrades.map { trade in
                    MappedTrade(
                        binanceTradeId: trade.id,
                        symbol: trade.symbol,
                        asset: asset,
                        price: Double(trade.price) ?? 0,
                        quantity: Double(trade.qty) ?? 0,
                        quoteQuantity: Double(trade.quoteQty) ?? 0,
                        commission: Double(trade.commission) ?? 0,
                        commissionAsset: trade.commissionAsset,
                        timestamp: Date(timeIntervalSince1970: Double(trade.time) / 1000),
                        isBuyer: trade.isBuyer,
                        orderId: trade.orderId
                    )
                }
                allTrades.append(contentsOf: mapped)

                if let lastTrade = assetTrades.last {
                    allSyncUpdates.append(SyncUpdate(
                        symbol: symbol,
                        lastTradeId: lastTrade.id,
                        syncDate: Date()
                    ))
                }

                logger.info("Isolated-margin: fetched \(assetTrades.count) trades for \(symbol)")
            } catch {
                logger.error("Isolated-margin: failed to fetch trades for \(symbol): \(error)")
                continue
            }

            if index < symbols.count - 1 {
                try? await Task.sleep(for: interRequestDelay)
            }
        }

        return TradeImportResult(
            mappedTrades: allTrades,
            syncUpdates: allSyncUpdates
        )
    }

    // MARK: - Retry


    /// Fetches all margin trades for a symbol with automatic pagination and rate-limit retry.
    private static func fetchMarginTradesWithRetry(
        apiClient: BinanceAPIClient,
        symbol: String,
        fromId: Int64?,
        isIsolated: Bool
    ) async throws -> [BinanceMarginTrade] {
        for attempt in 0..<maxRateLimitRetries {
            do {
                return try await fetchMarginTradesWithPagination(
                    apiClient: apiClient,
                    symbol: symbol,
                    fromId: fromId,
                    isIsolated: isIsolated
                )
            } catch let error as BinanceError {
                switch error {
                case .rateLimited(let retryAfterSeconds):
                    if attempt < maxRateLimitRetries - 1 {
                        let delayMs = retryAfterSeconds.map { $0 * 1000 }
                            ?? [500, 1500, 3000][attempt]
                        logger.warning(
                            "Rate limited fetching \(symbol) (isolated=\(isIsolated)), retrying in \(delayMs)ms (attempt \(attempt + 1)/\(maxRateLimitRetries))"
                        )
                        try? await Task.sleep(for: .milliseconds(delayMs))
                    } else {
                        logger.error(
                            "Rate limited fetching \(symbol) after \(maxRateLimitRetries) retries, skipping"
                        )
                        throw error
                    }
                case .invalidCredentials, .noCredentialsConfigured:
                    throw error
                default:
                    if attempt < maxRateLimitRetries - 1 {
                        let backoff = [500, 1500, 3000][min(attempt, 2)]
                        logger.warning(
                            "Error fetching \(symbol): \(error), retrying in \(backoff)ms"
                        )
                        try? await Task.sleep(for: .milliseconds(backoff))
                    } else {
                        throw error
                    }
                }
            } catch {
                if attempt < maxRateLimitRetries - 1 {
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    throw error
                }
            }
        }
        return []
    }

    /// Fetches all margin trades for a single symbol with automatic pagination.
    private static func fetchMarginTradesWithPagination(
        apiClient: BinanceAPIClient,
        symbol: String,
        fromId: Int64?,
        isIsolated: Bool
    ) async throws -> [BinanceMarginTrade] {
        var allTrades: [BinanceMarginTrade] = []
        var currentFromId = fromId

        while true {
            let batch = try await apiClient.fetchMarginMyTrades(symbol, currentFromId, isIsolated)
            allTrades.append(contentsOf: batch)

            guard batch.count >= 1000 else { break }
            guard let lastId = batch.last?.id else { break }
            currentFromId = lastId + 1
        }

        return allTrades
    }
}

// MARK: - Preview & Noop

extension MarginTradeImportService {
    static let preview = MarginTradeImportService(
        sync: { mode, existingSync in
            TradeImportResult(
                mappedTrades: [
                    MappedTrade(
                        binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
                        price: 50000, quantity: 0.5, quoteQuantity: 25000,
                        commission: 0.001, commissionAsset: "BTC",
                        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                        isBuyer: true, orderId: 100
                    ),
                    MappedTrade(
                        binanceTradeId: 2, symbol: "ETHUSDT", asset: "ETH",
                        price: 3000, quantity: 5.0, quoteQuantity: 15000,
                        commission: 0.01, commissionAsset: "ETH",
                        timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        isBuyer: true, orderId: 101
                    ),
                ],
                syncUpdates: [
                    SyncUpdate(symbol: "cross", lastTradeId: 1, syncDate: Date()),
                ]
            )
        }
    )

    static let noop = MarginTradeImportService(
        sync: { _, _ in .empty }
    )
}
