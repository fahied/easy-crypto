//
//  CrossMarginAccountData.swift
//  EasyCrypto
//
//  ADV-CORE-SERVICES-007: Cross-margin account snapshot with per-asset interest breakdown.
//  All numeric fields are decoded as Doubles — callers never handle raw strings.

import Foundation

// MARK: - Cross-Margin Account Snapshot

nonisolated struct CrossMarginAccountData: Sendable {
    let marginLevel: Double
    let totalAsset: Double
    let totalLiability: Double
    let totalNetAsset: Double
    let totalAssetOfBtc: Double
    let totalLiabilityOfBtc: Double
    let totalNetAssetOfBtc: Double
    let maxBorrowable: Double
    let maintained: Double?
    let perAssetInterest: [String: Double]

    /// Convenience alias matching the API's `totalNetAsset`.
    var netAsset: Double { totalNetAsset }

    init(
        marginLevel: Double,
        totalAsset: Double,
        totalLiability: Double,
        totalNetAsset: Double,
        totalAssetOfBtc: Double,
        totalLiabilityOfBtc: Double,
        totalNetAssetOfBtc: Double,
        maxBorrowable: Double,
        maintained: Double? = nil,
        perAssetInterest: [String: Double] = [:]
    ) {
        self.marginLevel = marginLevel
        self.totalAsset = totalAsset
        self.totalLiability = totalLiability
        self.totalNetAsset = totalNetAsset
        self.totalAssetOfBtc = totalAssetOfBtc
        self.totalLiabilityOfBtc = totalLiabilityOfBtc
        self.totalNetAssetOfBtc = totalNetAssetOfBtc
        self.maxBorrowable = maxBorrowable
        self.maintained = maintained
        self.perAssetInterest = perAssetInterest
    }

    init(from account: BinanceMarginAccount) throws {
        self.marginLevel = Double(account.marginLevel) ?? 0
        self.totalAsset = Double(account.totalAsset ?? "") ?? 0
        self.totalLiability = Double(account.totalLiability ?? "") ?? 0
        self.totalNetAsset = Double(account.totalNetAsset ?? "") ?? 0
        self.totalAssetOfBtc = Double(account.totalAssetOfBtc) ?? 0
        self.totalLiabilityOfBtc = Double(account.totalLiabilityOfBtc) ?? 0
        self.totalNetAssetOfBtc = Double(account.totalNetAssetOfBtc) ?? 0
        self.maxBorrowable = Double(account.maxBorrowable ?? "") ?? 0
        self.maintained = account.maintained.flatMap(Double.init)

        var interestMap: [String: Double] = [:]
        for entry in account.userAssets ?? [] {
            guard let asset = entry.asset else { continue }
            if let interest = Double(entry.interest), interest != 0 {
                interestMap[asset] = interest
            }
        }
        self.perAssetInterest = interestMap
    }
}
