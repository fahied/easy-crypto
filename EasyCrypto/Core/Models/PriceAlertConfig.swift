//
//  PriceAlertConfig.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Per-symbol configuration for background profit-threshold price alerts.
///
/// `lastNotifiedProfit` is the baseline unrealized profit at the time the most
/// recent alert fired; a new alert fires only once the current profit exceeds
/// this baseline by at least `thresholdUSD`.
@Model
final class PriceAlertConfig {
    #Unique<PriceAlertConfig>([\.symbol])

    var symbol: String
    var isEnabled: Bool
    var thresholdUSD: Double
    var lastNotifiedProfit: Double

    init(
        symbol: String,
        isEnabled: Bool = false,
        thresholdUSD: Double = 100,
        lastNotifiedProfit: Double = 0
    ) {
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.thresholdUSD = thresholdUSD
        self.lastNotifiedProfit = lastNotifiedProfit
    }
}
