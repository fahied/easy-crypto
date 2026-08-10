//
//  HoldingsIntent.swift
//  EasyCrypto
//

import Foundation

enum HoldingsIntent: Intent {
    case loadHoldings
    case setTradingMode(TradingMode)
}
