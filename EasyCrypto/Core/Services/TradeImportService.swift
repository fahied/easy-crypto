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
    /// `existingSync` maps symbol (e.g. "BTCUSDT") → lastTradeId for incremental sync.
    var sync: @Sendable (_ existingSync: [String: Int64]) async throws -> TradeImportResult
}

// MARK: - Live Implementation

extension TradeImportService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "sync"
    )

    nonisolated private static let bootstrapTrackedAssets = [
        "BTC",
        "SOL",
        "IOTX",
        "BNB",
    ]

    static func live(apiClient: BinanceAPIClient) -> TradeImportService {
        TradeImportService(
            sync: { existingSync in
                // 1. Discover assets from account
                let balances = try await apiClient.fetchAccount()
                let balanceAssets = balances
                    .map(\.asset)
                    .filter { $0 != "USDT" }
                let previouslySyncedAssets = existingSync.keys
                    .filter { $0.hasSuffix("USDT") }
                    .map { String($0.dropLast(4)) }
                let assets = Array(
                    Set(balanceAssets + previouslySyncedAssets + bootstrapTrackedAssets)
                ).sorted()

                guard !assets.isEmpty else {
                    logger.info("No non-USDT assets found in account")
                    return .empty
                }

                logger.info("Discovered \(assets.count) assets: \(assets.joined(separator: ", "))")

                var allTrades: [MappedTrade] = []
                var syncUpdates: [SyncUpdate] = []

                // 2. For each asset, fetch trades with pagination
                for asset in assets {
                    let symbol = "\(asset)USDT"
                    let lastTradeId = existingSync[symbol]
                    let startFromId = lastTradeId.map { $0 + 1 }

                    do {
                        let assetTrades = try await fetchTradesWithPagination(
                            apiClient: apiClient,
                            symbol: symbol,
                            fromId: startFromId
                        )

                        // Map API responses to domain objects
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

                        // Update sync metadata
                        if let lastTrade = assetTrades.last {
                            syncUpdates.append(SyncUpdate(
                                symbol: symbol,
                                lastTradeId: lastTrade.id,
                                syncDate: Date()
                            ))
                        }

                        logger.info("Fetched \(assetTrades.count) trades for \(symbol)")
                    } catch {
                        logger.error("Failed to fetch trades for \(symbol): \(error)")
                        continue
                    }
                }

                return TradeImportResult(
                    mappedTrades: allTrades,
                    syncUpdates: syncUpdates
                )
            }
        )
    }

    /// Fetches all trades for a symbol with automatic pagination.
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
