//
//  PriceService.swift
//  EasyCrypto
//

import Foundation
import os

// MARK: - Service (struct-with-closures pattern)

nonisolated struct PriceService: Sendable {
    /// Fetches current USDT prices for the given symbols.
    /// Returns a map of symbol (e.g. "BTCUSDT") → price in USDT.
    var fetchPrices: @Sendable (_ symbols: [String]) async throws -> [String: Double]
}

// MARK: - Live Implementation

extension PriceService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "prices"
    )

    static func live(apiClient: BinanceAPIClient) -> PriceService {
        PriceService(
            fetchPrices: { symbols in
                guard !symbols.isEmpty else { return [:] }

                let tickers = try await apiClient.fetchTickerPrices(symbols)
                var priceMap: [String: Double] = [:]
                for ticker in tickers {
                    if let price = Double(ticker.price) {
                        priceMap[ticker.symbol] = price
                    }
                }

                logger.info("Fetched prices for \(priceMap.count) symbols")
                return priceMap
            }
        )
    }
}

// MARK: - Preview & Noop

extension PriceService {
    static let preview = PriceService(
        fetchPrices: { _ in
            ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0]
        }
    )

    static let noop = PriceService(
        fetchPrices: { _ in [:] }
    )
}
