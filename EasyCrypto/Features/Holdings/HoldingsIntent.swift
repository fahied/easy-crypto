//
//  HoldingsIntent.swift
//  EasyCrypto
//

import Foundation

enum HoldingsIntent: Intent {
    case loadHoldings
    case loadPersisted
    case setTradingMode(TradingMode)
}
