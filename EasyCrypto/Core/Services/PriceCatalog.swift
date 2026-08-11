//
//  PriceCatalog.swift
//  EasyCrypto
//
//  Hard-coded set of USDT pairs the app cares about. All price lookups
//  are filtered to this list so we never hit the exchange with symbols
//  that aren't in the user's trading universe.

import Foundation

struct PriceCatalog {
    static let symbols: Set<String> = [
        "ADA", "ALLO", "BANK", "BCH", "BNB", "BTC",
        "DEXE", "ETH", "HYPER", "IOTA", "LTC", "MET",
        "MMT", "NEAR", "SENT", "SOL", "TRX", "XRP",
    ]

    /// Builds a ["BTCUSDT", "ETHUSDT", …] list from an asset set,
    /// excluding the given asset (e.g. "USDT") and filtering to
    /// the curated catalog.
    static func usdtSymbols(from assets: [String], exclude: String = "USDT") -> [String] {
        assets
            .filter { $0 != exclude && symbols.contains($0) }
            .map { "\($0)USDT" }
    }
}
