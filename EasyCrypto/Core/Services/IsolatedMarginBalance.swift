//
//  IsolatedMarginBalance.swift
//  EasyCrypto
//
//  ADV-CORE-SERVICES-007: Per-asset balance for an isolated-margin trading pair.
//  Combines borrowed/free/locked/interest from fetchMarginAllAssets with
//  liquidationPrice and marginLevel from fetchIsolatedMarginAccount.

import Foundation

// MARK: - Isolated Margin Balance

nonisolated struct IsolatedMarginBalance: Sendable, Identifiable {
    /// The isolated trading pair symbol (e.g. "BTCUSDT").
    let symbol: String
    /// The individual asset within the pair (e.g. "BTC" or "USDT").
    let asset: String
    let borrowed: Double
    let free: Double
    let locked: Double
    let interest: Double
    let netAsset: Double
    /// Liquidation price for the pair — sourced from `fetchIsolatedMarginAccount`.
    let liquidationPrice: String
    /// Margin level for the pair — sourced from `fetchIsolatedMarginAccount`.
    let marginLevel: String

    var id: String { "\(symbol):\(asset)" }

    init(
        symbol: String,
        asset: String,
        borrowed: Double = 0,
        free: Double = 0,
        locked: Double = 0,
        interest: Double = 0,
        netAsset: Double = 0,
        liquidationPrice: String = "",
        marginLevel: String = ""
    ) {
        self.symbol = symbol
        self.asset = asset
        self.borrowed = borrowed
        self.free = free
        self.locked = locked
        self.interest = interest
        self.netAsset = netAsset
        self.liquidationPrice = liquidationPrice
        self.marginLevel = marginLevel
    }

    // MARK: - Builder

    static func from(
        assetDetail: BinanceIsolatedMarginAccount.AssetDetail,
        symbol: String,
        liquidationPrice: String = "",
        marginLevel: String = ""
    ) -> IsolatedMarginBalance {
        IsolatedMarginBalance(
            symbol: symbol,
            asset: assetDetail.asset,
            borrowed: Double(assetDetail.borrowed) ?? 0,
            free: Double(assetDetail.free) ?? 0,
            locked: Double(assetDetail.locked) ?? 0,
            interest: Double(assetDetail.interest) ?? 0,
            netAsset: Double(assetDetail.netAsset) ?? 0,
            liquidationPrice: liquidationPrice,
            marginLevel: marginLevel
        )
    }
}
