//
//  TradingMode.swift
//  EasyCrypto
//
//  Distinguishes spot, cross-margin, and isolated-margin trading modes.
//  Used as a filter key across Trade, AccountBalance, and SyncMetadata
//  so the same symbol can have independent data per mode.

import Foundation

enum TradingMode: String, Codable, CaseIterable, Sendable, Comparable {
    case spot = "spot"
    case crossMargin = "cross_margin"
    case isolatedMargin = "isolated_margin"

    static func < (lhs: TradingMode, rhs: TradingMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .spot: "Spot"
        case .crossMargin: "Cross Margin"
        case .isolatedMargin: "Isolated Margin"
        }
    }
}
