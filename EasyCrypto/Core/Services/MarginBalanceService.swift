//
//  MarginBalanceService.swift
//  EasyCrypto
//
//  ADV-CORE-SERVICES-007: Margin balance aggregation service. Wraps Binance margin
//  balance endpoints to produce cross-margin snapshots and isolated-margin per-symbol
//  balance maps. All numeric fields are Doubles — callers never handle raw strings.

import Foundation
import os

// MARK: - Service (struct-with-closures pattern)

nonisolated struct MarginBalanceService: Sendable {
    /// Cross-margin account snapshot. Returns nil when the user has no cross-margin positions.
    var fetchCrossMarginAccount: @Sendable () async throws -> CrossMarginAccountData?

    /// Per-asset balances for cross-margin derived from the account snapshot.
    /// Each entry contains borrowed, free, locked, netAsset, and interest.
    var fetchCrossMarginBalances: @Sendable () async throws -> [CrossMarginBalance]

    /// Isolated-margin balances for the given isolated pair symbol (e.g. "BTCUSDT").
    /// Returns per-asset balances built from `fetchIsolatedMarginAccount` which includes
    /// borrowed/free/locked/interest per asset plus liquidationPrice/marginLevel at pair level.
    var fetchIsolatedMarginBalances: @Sendable (_ symbol: String) async throws -> [IsolatedMarginBalance]?

    /// Isolated-margin balances for *every* pair the account has open, discovered by
    /// querying `/sapi/v1/margin/isolated/account` without a `symbols` filter.
    /// Callers with no prior knowledge of the user's pairs must use this.
    var fetchAllIsolatedMarginBalances: @Sendable () async throws -> [IsolatedMarginBalance]

    init(
        fetchCrossMarginAccount: @escaping @Sendable () async throws -> CrossMarginAccountData?,
        fetchCrossMarginBalances: @escaping @Sendable () async throws -> [CrossMarginBalance],
        fetchIsolatedMarginBalances: @escaping @Sendable (_ symbol: String) async throws -> [IsolatedMarginBalance]?,
        fetchAllIsolatedMarginBalances: @escaping @Sendable () async throws -> [IsolatedMarginBalance] = { [] }
    ) {
        self.fetchCrossMarginAccount = fetchCrossMarginAccount
        self.fetchCrossMarginBalances = fetchCrossMarginBalances
        self.fetchIsolatedMarginBalances = fetchIsolatedMarginBalances
        self.fetchAllIsolatedMarginBalances = fetchAllIsolatedMarginBalances
    }
}

// MARK: - Live Implementation

extension MarginBalanceService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "margin-balance"
    )

    static func live(apiClient: BinanceAPIClient) -> MarginBalanceService {
        MarginBalanceService(
            fetchCrossMarginAccount: {
                let account = try await apiClient.fetchMarginAccount()
                guard !(account.userAssets ?? []).isEmpty else {
                    logger.info("Cross-margin account empty — returning nil")
                    return nil
                }
                let data = try CrossMarginAccountData(from: account)
                logger.info(
                    "Fetched cross-margin snapshot (netAsset: \(data.netAsset, privacy: .public))"
                )
                return data
            },
            fetchCrossMarginBalances: {
                let account = try await apiClient.fetchMarginAccount()
                let balances = account.userAssets?
                    .compactMap { entry -> CrossMarginBalance? in
                        guard let asset = entry.asset else { return nil }
                        let borrowed = Double(entry.borrowed) ?? 0
                        let free = Double(entry.free) ?? 0
                        let locked = Double(entry.locked) ?? 0
                        let interest = Double(entry.interest) ?? 0
                        let netAsset = Double(entry.netAsset) ?? (free + locked - borrowed - interest)
                        return CrossMarginBalance(
                            asset: asset,
                            borrowed: borrowed,
                            free: free,
                            locked: locked,
                            netAsset: netAsset,
                            interest: interest
                        )
                    } ?? []
                logger.info("Fetched \(balances.count) cross-margin balances")
                return balances
            },
            fetchIsolatedMarginBalances: { symbol in
                // fetchIsolatedMarginAccount returns per-symbol IsolatedPair entries,
                // each containing baseAsset + quoteAsset (with borrowed/free/locked/interest)
                // and pair-level liquidationPrice + marginLevel.
                let isolatedAccount = try await apiClient.fetchIsolatedMarginAccount([symbol])

                guard !isolatedAccount.assets.isEmpty else {
                    logger.info("No isolated-margin pairs found for \(symbol)")
                    return []
                }

                let balances: [IsolatedMarginBalance] = isolatedAccount.assets.flatMap { pair in
                    [
                        IsolatedMarginBalance.from(
                            assetDetail: pair.baseAsset,
                            symbol: pair.symbol,
                            role: .base,
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                        IsolatedMarginBalance.from(
                            assetDetail: pair.quoteAsset,
                            symbol: pair.symbol,
                            role: .quote,
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                    ]
                }

                logger.info("Fetched \(balances.count) isolated-margin balances for \(symbol)")
                return balances
            },
            fetchAllIsolatedMarginBalances: {
                // No `symbols` filter — Binance then returns every isolated pair the
                // account has created, which is the only way to discover them.
                let isolatedAccount = try await apiClient.fetchIsolatedMarginAccount([])
                let balances = isolatedAccount.assets.flatMap { pair in
                    [
                        IsolatedMarginBalance.from(
                            assetDetail: pair.baseAsset,
                            symbol: pair.symbol,
                            role: .base,
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                        IsolatedMarginBalance.from(
                            assetDetail: pair.quoteAsset,
                            symbol: pair.symbol,
                            role: .quote,
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                    ]
                }
                logger.info("Fetched \(balances.count) isolated-margin balances across \(isolatedAccount.assets.count) pairs")
                return balances
            }
        )
    }
}

// MARK: - Preview & Noop

extension MarginBalanceService {
    static let preview = MarginBalanceService(
        fetchCrossMarginAccount: {
            CrossMarginAccountData(
                marginLevel: 3.5,
                totalAsset: 10000,
                totalLiability: 2800,
                totalNetAsset: 7200,
                totalAssetOfBtc: 0.15,
                totalLiabilityOfBtc: 0.04,
                totalNetAssetOfBtc: 0.11,
                maxBorrowable: 5000,
                maintained: nil,
                perAssetInterest: ["BTC": 0.001, "SOL": 0.0005]
            )
        },
        fetchCrossMarginBalances: {
            [
                CrossMarginBalance(asset: "BTC", borrowed: 0.5, free: 0.2, locked: 0.1, netAsset: -0.201, interest: 0.001),
                CrossMarginBalance(asset: "USDT", borrowed: 10000, free: 500, locked: 0, netAsset: -9500, interest: 0),
            ]
        },
        fetchIsolatedMarginBalances: { symbol in
            [
                IsolatedMarginBalance(
                    symbol: symbol,
                    asset: "BTC",
                    role: .base,
                    borrowed: 0.5,
                    free: 0.2,
                    locked: 0.1,
                    netAsset: -0.201,
                    liquidationPrice: "42000",
                    marginLevel: "2.1"
                ),
                IsolatedMarginBalance(
                    symbol: symbol,
                    asset: "USDT",
                    role: .quote,
                    borrowed: 10000,
                    free: 500,
                    locked: 0,
                    netAsset: -9500
                ),
            ]
        },
        fetchAllIsolatedMarginBalances: {
            [
                IsolatedMarginBalance(
                    symbol: "BTCUSDT",
                    asset: "BTC",
                    role: .base,
                    borrowed: 0.5,
                    free: 0.2,
                    locked: 0.1,
                    netAsset: -0.201,
                    liquidationPrice: "42000",
                    marginLevel: "2.1"
                ),
                IsolatedMarginBalance(
                    symbol: "BTCUSDT",
                    asset: "USDT",
                    role: .quote,
                    borrowed: 10000,
                    free: 500,
                    locked: 0,
                    netAsset: -9500
                ),
            ]
        }
    )

    static let noop = MarginBalanceService(
        fetchCrossMarginAccount: { nil },
        fetchCrossMarginBalances: { [] },
        fetchIsolatedMarginBalances: { _ in nil },
        fetchAllIsolatedMarginBalances: { [] }
    )
}
