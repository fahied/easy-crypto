//
//  CrossMarginBalance.swift
//
//  Persists cross-margin per-asset balances from the account snapshot.
//  Complements MarginBalance (isolated-margin) and AccountBalance (spot).
//
//  ADV-CORE-PERSISTENCE-005: Cross-margin balance persistence.

import Foundation
import SwiftData

/// Per-asset balance snapshot for cross-margin mode.
///
/// Derived from `BinanceMarginAccount.userAssets` (which returns borrowed, free,
/// locked, interest, and netAsset per asset). Persisted on each portfolio refresh
/// so the Holdings and Portfolio tabs can display quantities that match the
/// Binance app offline.
///
/// Cross-margin has no isolated pair concept — the entire margin account is one
/// shared pool — so a unique constraint on `(asset, tradingMode)` is sufficient.
@Model
final class CrossMarginBalance {
    #Unique<CrossMarginBalance>([\.asset, \.tradingMode])

    var asset: String
    var borrowed: Double
    var free: Double
    var locked: Double
    var netAsset: Double
    var interest: Double
    var updatedAt: Date
    var tradingMode: String

    init(
        asset: String,
        borrowed: Double = 0,
        free: Double = 0,
        locked: Double = 0,
        netAsset: Double = 0,
        interest: Double = 0,
        updatedAt: Date = Date(),
        tradingMode: TradingMode = .crossMargin
    ) {
        self.asset = asset
        self.borrowed = borrowed
        self.free = free
        self.locked = locked
        self.netAsset = netAsset
        self.interest = interest
        self.updatedAt = updatedAt
        self.tradingMode = tradingMode.rawValue
    }

    var tradingModeEnum: TradingMode {
        TradingMode(rawValue: tradingMode) ?? .crossMargin
    }
}
