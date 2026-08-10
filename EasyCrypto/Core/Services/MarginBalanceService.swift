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

    /// Isolated-margin balances for the given isolated pair symbol (e.g. "BTCUSDT").
    /// Returns per-asset balances built from `fetchIsolatedMarginAccount` which includes
    /// borrowed/free/locked/interest per asset plus liquidationPrice/marginLevel at pair level.
    var fetchIsolatedMarginBalances: @Sendable (_ symbol: String) async throws -> [IsolatedMarginBalance]?
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
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                        IsolatedMarginBalance.from(
                            assetDetail: pair.quoteAsset,
                            symbol: pair.symbol,
                            liquidationPrice: pair.liquidatePrice,
                            marginLevel: pair.marginLevel
                        ),
                    ]
                }

                logger.info("Fetched \(balances.count) isolated-margin balances for \(symbol)")
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
        fetchIsolatedMarginBalances: { symbol in
            [
                IsolatedMarginBalance(
                    symbol: symbol,
                    asset: "BTC",
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
        fetchIsolatedMarginBalances: { _ in nil }
    )
}
