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
    enum Role: String, Sendable {
        case base
        case quote
    }

    let symbol: String
    let asset: String
    let role: Role
    let borrowed: Double
    let free: Double
    let locked: Double
    let interest: Double
    let netAsset: Double
    let liquidationPrice: String
    let marginLevel: String

    var id: String { "\(symbol):\(asset):\(role.rawValue)" }

    init(
        symbol: String,
        asset: String,
        role: Role,
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
        self.role = role
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
        role: Role,
        liquidationPrice: String = "",
        marginLevel: String = ""
    ) -> IsolatedMarginBalance {
        IsolatedMarginBalance(
            symbol: symbol,
            asset: assetDetail.asset,
            role: role,
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
