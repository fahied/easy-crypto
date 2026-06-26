//
//  PriceAlertConfig.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Per-symbol configuration for background profit-threshold price alerts.
///
/// `lastNotifiedProfit` / `lastNotifiedLoss` are the baseline unrealized profits at
/// the time the most recent gain / loss alert fired. A gain alert fires only once
/// the current profit rises `thresholdUSD` above `lastNotifiedProfit`; a loss alert
/// fires only once it falls `thresholdUSD` below `lastNotifiedLoss`.
@Model
final class PriceAlertConfig {
    #Unique<PriceAlertConfig>([\.symbol])

    var symbol: String
    var isEnabled: Bool
    var thresholdUSD: Double
    var lastNotifiedProfit: Double
    var lastNotifiedLoss: Double = 0
    var percentThreshold: Double = 5
    var referencePrice: Double = 0

    init(
        symbol: String,
        isEnabled: Bool = false,
        thresholdUSD: Double = 100,
        lastNotifiedProfit: Double = 0,
        lastNotifiedLoss: Double = 0,
        percentThreshold: Double = 5,
        referencePrice: Double = 0
    ) {
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.thresholdUSD = thresholdUSD
        self.lastNotifiedProfit = lastNotifiedProfit
        self.lastNotifiedLoss = lastNotifiedLoss
        self.percentThreshold = percentThreshold
        self.referencePrice = referencePrice
    }
}
