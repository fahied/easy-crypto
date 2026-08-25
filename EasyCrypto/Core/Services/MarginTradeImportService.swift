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

    nonisolated private static let maxConcurrentFetches = 4

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

    // MARK: - Static Asset Lists

    nonisolated static let knownCrossMarginAssets: [String] = [
        "SOL", "DEXE", "MMT", "BANK", "LTC", "XRP"
    ]

    nonisolated static let knownIsolatedMarginAssets: [String] = [
        "DEXE", "MMT", "XRP"
    ]

    // MARK: - Cross-Margin Sync

    /// Cross-margin keeps one sync cursor per symbol, since Binance trade ids are
    /// per-symbol — a shared cursor would skip whole ranges on every other symbol.
    private static func syncCrossMargin(
        apiClient: BinanceAPIClient,
        existingSync: [String: Int64]
    ) async throws -> TradeImportResult {
        let assets = Self.knownCrossMarginAssets

        guard !assets.isEmpty else {
            logger.info("No assets found for cross-margin sync")
            return .empty
        }

        logger.info("Cross-margin: syncing \(assets.count) assets")

        var allTrades: [MappedTrade] = []
        var allSyncUpdates: [SyncUpdate] = []

        let semaphore = AsyncSemaphore(bitPattern: Self.maxConcurrentFetches)

        try await withThrowingTaskGroup(of: MarginPerAssetResult.self) { group in
            for asset in assets {
                let symbol = "\(asset)USDT"
                let startFromId = existingSync[symbol].map { $0 + 1 }

                group.addTask {
                    await semaphore.wait()
                    defer { await semaphore.signal() }
                    return await Self.fetchMarginTradesForAsset(
                        apiClient: apiClient,
                        symbol: symbol,
                        asset: asset,
                        fromId: startFromId,
                        isIsolated: false
                    )
                }
            }

            for try await result in group {
                allTrades.append(contentsOf: result.trades)
                if let lastTradeId = result.lastTradeId {
                    allSyncUpdates.append(SyncUpdate(
                        symbol: result.symbol,
                        lastTradeId: lastTradeId,
                        syncDate: Date()
                    ))
                }
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
        let symbols = Self.knownIsolatedMarginAssets.map { "\($0)USDT" }

        guard !symbols.isEmpty else {
            logger.info("No isolated-margin symbols found for sync")
            return .empty
        }

        logger.info("Isolated-margin: syncing \(symbols.count) symbols")

        var allTrades: [MappedTrade] = []
        var allSyncUpdates: [SyncUpdate] = []

        let semaphore = AsyncSemaphore(bitPattern: Self.maxConcurrentFetches)

        try await withThrowingTaskGroup(of: MarginPerAssetResult.self) { group in
            for symbol in symbols {
                let asset = String(symbol.dropLast(4))  // strip "USDT"
                let lastTradeId = existingSync[symbol]
                let startFromId = lastTradeId.map { $0 + 1 }

                group.addTask {
                    await semaphore.wait()
                    defer { await semaphore.signal() }
                    return await Self.fetchMarginTradesForAsset(
                        apiClient: apiClient,
                        symbol: symbol,
                        asset: asset,
                        fromId: startFromId,
                        isIsolated: true
                    )
                }
            }

            for try await result in group {
                allTrades.append(contentsOf: result.trades)
                if let lastTradeId = result.lastTradeId {
                    allSyncUpdates.append(SyncUpdate(
                        symbol: result.symbol,
                        lastTradeId: lastTradeId,
                        syncDate: Date()
                    ))
                }
            }
        }

        return TradeImportResult(
            mappedTrades: allTrades,
            syncUpdates: allSyncUpdates
        )
    }

    // MARK: - Trade Fetching

    private struct MarginPerAssetResult: Sendable {
        let symbol: String
        let asset: String
        let trades: [MappedTrade]
        let lastTradeId: Int64?
    }

    private static func fetchMarginTradesForAsset(
        apiClient: BinanceAPIClient,
        symbol: String,
        asset: String,
        fromId: Int64?,
        isIsolated: Bool
    ) async -> MarginPerAssetResult {
        let assetTrades: [BinanceMarginTrade]
        do {
            assetTrades = try await fetchMarginTradesWithPagination(
                apiClient: apiClient,
                symbol: symbol,
                fromId: fromId,
                isIsolated: isIsolated
            )
        } catch {
            logger.warning("Failed to fetch trades for \(symbol): \(error), skipping")
            return MarginPerAssetResult(symbol: symbol, asset: asset, trades: [], lastTradeId: nil)
        }

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

        logger.info("Fetched \(assetTrades.count) trades for \(symbol) (isolated=\(isIsolated))")

        return MarginPerAssetResult(
            symbol: symbol,
            asset: asset,
            trades: mapped,
            lastTradeId: assetTrades.last?.id
        )
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
