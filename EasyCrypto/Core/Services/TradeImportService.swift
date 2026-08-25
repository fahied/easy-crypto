//
//  TradeImportService.swift
//  EasyCrypto
//

import Foundation
import os

// MARK: - Types

/// A trade mapped from the Binance API, ready for SwiftData persistence.
nonisolated struct MappedTrade: Equatable, Sendable {
    let binanceTradeId: Int64
    let symbol: String
    let asset: String
    let price: Double
    let quantity: Double
    let quoteQuantity: Double
    let commission: Double
    let commissionAsset: String
    let timestamp: Date
    let isBuyer: Bool
    let orderId: Int64
}

/// Sync metadata update for a single symbol.
nonisolated struct SyncUpdate: Sendable {
    let symbol: String
    let lastTradeId: Int64
    let syncDate: Date
}

/// Result of a full trade import operation.
nonisolated struct TradeImportResult: Sendable {
    let mappedTrades: [MappedTrade]
    let syncUpdates: [SyncUpdate]

    static let empty = TradeImportResult(mappedTrades: [], syncUpdates: [])
}

// MARK: - Service (struct-with-closures pattern)

nonisolated struct TradeImportService: Sendable {
    /// Performs full trade sync: discovers assets, fetches trades with pagination.
    /// `existingSync` maps symbol (e.g. "BTCUSDT") -> lastTradeId for incremental sync.
    var sync: @Sendable (_ existingSync: [String: Int64]) async throws -> TradeImportResult
}

// MARK: - Static Asset List

extension TradeImportService {
    /// Assets the user actively trades. Always included in sync regardless of
    /// current balance — closed positions need their trade history preserved.
    nonisolated static let knownAssets: [String] = [
        "ADA", "ALLO", "BANK", "BCH", "BNB", "BTC", "DEXE", "ETH",
        "HYPER", "IOTA", "LTC", "MET", "MMT", "NEAR", "SENT",
        "SOL", "TRX", "XRP"
    ]
}

// MARK: - Live Implementation

extension TradeImportService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "sync"
    )

    nonisolated private static let maxConcurrentFetches = 4
    nonisolated private static let interRequestDelay: Duration = .milliseconds(300)

    /// Maximum retries per symbol when a 429 rate-limit response is received.
    nonisolated private static let maxRateLimitRetries = 3

    static func live(
        apiClient: BinanceAPIClient
    ) -> TradeImportService {
        TradeImportService(
            sync: { existingSync in
                let balances = try await apiClient.fetchAccount()
                let previouslySyncedAssets = existingSync.keys
                    .filter { $0.hasSuffix("USDT") }
                    .map { String($0.dropLast(4)) }

                let balanceDiscoveredAssets = Set(
                    balances
                        .filter { $0.asset != "USDT" }
                        .compactMap { $0.asset }
                )

                // Static list is always included — closed positions must stay synced.
                let staticAssets = Set(Self.knownAssets)
                let knownAssets = Set(previouslySyncedAssets)

                let assets = Array(
                    staticAssets.union(balanceDiscoveredAssets).union(knownAssets)
                )
                .sorted()

                guard !assets.isEmpty else {
                    logger.info("No non-USDT assets found in account")
                    return TradeImportResult.empty
                }

                logger.info("Discovered \(assets.count) assets: \(assets.joined(separator: ", "))")

                let semaphore = AsyncSemaphore(bitPattern: Self.maxConcurrentFetches)

                let allResults: [PerAssetResult] = try await withThrowingTaskGroup(
                    of: PerAssetResult.self,
                    returning: [PerAssetResult].self
                ) { group in
                    for asset in assets {
                        let symbol = "\(asset)USDT"
                        let lastTradeId = existingSync[symbol]
                        let startFromId = lastTradeId.map { $0 + 1 }

                        group.addTask {
                            await semaphore.wait()
                            let result = try await Self.fetchTradesForAsset(
                                apiClient: apiClient,
                                asset: asset,
                                fromId: startFromId
                            )
                            await semaphore.signal()
                            return result
                        }
                    }

                    var collected: [PerAssetResult] = []
                    for try await r in group {
                        collected.append(r)
                    }
                    return collected
                }

                let allTrades = allResults.flatMap(\.trades)
                let syncUpdates = allResults.compactMap { r -> SyncUpdate? in
                    guard let maxId = r.trades.map(\.binanceTradeId).max() else { return nil }
                    return SyncUpdate(
                        symbol: "\(r.asset)USDT",
                        lastTradeId: maxId,
                        syncDate: Date()
                    )
                }

                return TradeImportResult(
                    mappedTrades: allTrades,
                    syncUpdates: syncUpdates
                )
            }
        )
    }

    // MARK: - Per-Asset Fetch

    private struct PerAssetResult: Sendable {
        let asset: String
        let trades: [MappedTrade]
        let lastTradeId: Int64?
    }

    private static func fetchTradesForAsset(
        apiClient: BinanceAPIClient,
        asset: String,
        fromId: Int64?
    ) async throws -> PerAssetResult {
        let assetTrades = try await fetchTradesWithRetry(
            apiClient: apiClient,
            symbol: "\(asset)USDT",
            fromId: fromId
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

        logger.info("Fetched \(assetTrades.count) trades for \(asset)USDT")

        return PerAssetResult(
            asset: asset,
            trades: mapped,
            lastTradeId: assetTrades.last?.id
        )
    }

    private static func fetchTradesWithRetry(
        apiClient: BinanceAPIClient,
        symbol: String,
        fromId: Int64?
    ) async throws -> [BinanceTrade] {
        for attempt in 0..<maxRateLimitRetries {
            do {
                return try await fetchTradesWithPagination(
                    apiClient: apiClient,
                    symbol: symbol,
                    fromId: fromId
                )
            } catch let error as BinanceError {
                switch error {
                case .rateLimited(let retryAfterSeconds):
                    if attempt < maxRateLimitRetries - 1 {
                        let delayMs = retryAfterSeconds.map { $0 * 1000 }
                            ?? [500, 1500, 3000][attempt]
                        logger.warning(
                            "Rate limited fetching \(symbol), retrying in \(delayMs)ms (attempt \(attempt + 1)/\(maxRateLimitRetries))"
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

    private static func fetchTradesWithPagination(
        apiClient: BinanceAPIClient,
        symbol: String,
        fromId: Int64?
    ) async throws -> [BinanceTrade] {
        var allTrades: [BinanceTrade] = []
        var currentFromId = fromId

        while true {
            let batch = try await apiClient.fetchMyTrades(symbol, currentFromId)
            allTrades.append(contentsOf: batch)

            guard batch.count >= 1000 else { break }
            guard let lastId = batch.last?.id else { break }
            currentFromId = lastId + 1
        }

        return allTrades
    }
}

// MARK: - Async Semaphore

/// Lightweight async semaphore built on continuations, usable from `Sendable` closures.
actor AsyncSemaphore: @unchecked Sendable {
    private let maximum: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(bitPattern: Int) {
        self.maximum = bitPattern
        self.available = bitPattern
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let next = waiters.popLast() {
            next.resume(returning: ())
        } else {
            available = min(available + 1, maximum)
        }
    }
}

// MARK: - Preview & Noop

extension TradeImportService {
    static let preview = TradeImportService(
        sync: { _ in
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
                    SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                    SyncUpdate(symbol: "ETHUSDT", lastTradeId: 2, syncDate: Date()),
                ]
            )
        }
    )

    static let noop = TradeImportService(
        sync: { _ in .empty }
    )
}
