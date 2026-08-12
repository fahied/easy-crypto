//
//  PriceCatalog.swift
//  EasyCrypto
//
//  Converts asset tickers to USDT trading-pair symbols for price lookups.
//  The set of known assets is built dynamically from the user's account
//  balances and trade-sync history — there is no hardcoded whitelist.

import Foundation

struct PriceCatalog {
    /// Builds a ["BTCUSDT", "ETHUSDT", …] list from an asset set,
    /// excluding the given asset (e.g. "USDT") which always has price 1.0.
    static func usdtSymbols(from assets: [String], exclude: String = "USDT") -> [String] {
        assets
            .filter { $0 != exclude }
            .map { "\($0)USDT" }
    }
}
