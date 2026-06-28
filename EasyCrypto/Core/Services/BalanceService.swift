//
//  BalanceService.swift
//  EasyCrypto
//

import Foundation
import os

// MARK: - Service (struct-with-closures pattern)

nonisolated struct BalanceService: Sendable {
    /// Returns the current non-zero wallet balances as `asset → quantity`
    /// (`free + locked`), the authoritative source for holding quantities.
    var fetchBalances: @Sendable () async throws -> [String: Double]
}

// MARK: - Live Implementation

extension BalanceService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "balances"
    )

    static func live(apiClient: BinanceAPIClient) -> BalanceService {
        BalanceService(
            fetchBalances: {
                let balances = try await apiClient.fetchAccount()
                var map: [String: Double] = [:]
                for balance in balances {
                    let quantity = (Double(balance.free) ?? 0) + (Double(balance.locked) ?? 0)
                    if quantity > 0 {
                        map[balance.asset] = quantity
                    }
                }
                logger.info("Fetched \(map.count) non-zero balances")
                return map
            }
        )
    }
}

// MARK: - Preview & Noop

extension BalanceService {
    static let preview = BalanceService(
        fetchBalances: { ["BTC": 0.5, "ETH": 10.0, "USDT": 5000.0] }
    )

    static let noop = BalanceService(
        fetchBalances: { [:] }
    )
}
