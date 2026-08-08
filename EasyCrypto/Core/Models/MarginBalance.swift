//
//  MarginBalance.swift
//  EasyCrypto
//
//  Persists isolated-margin per-asset balances (borrowed, free, locked, interest).
//  Cross-margin balances are a view-level derivation from the account snapshot
//  and are not persisted here.

import Foundation
import SwiftData

@Model
final class MarginBalance {
    #Unique<MarginBalance>([\.symbol, \.isolatedMarginKey])

    var symbol: String
    var isolatedMarginKey: String
    var asset: String
    var borrowed: Double
    var free: Double
    var locked: Double
    var interest: Double
    var updatedAt: Date

    init(
        symbol: String,
        isolatedMarginKey: String,
        asset: String,
        borrowed: Double = 0,
        free: Double = 0,
        locked: Double = 0,
        interest: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.symbol = symbol
        self.isolatedMarginKey = isolatedMarginKey
        self.asset = asset
        self.borrowed = borrowed
        self.free = free
        self.locked = locked
        self.interest = interest
        self.updatedAt = updatedAt
    }

    var netAsset: Double {
        free + locked - borrowed - interest
    }
}
