//
//  TradeHistoryIntent.swift
//  EasyCrypto
//

import Foundation

enum TradeHistoryIntent: Intent {
    case loadHistory
    case filterByCoin(String?)
    case filterByMode(TradingMode?)
    case nextMonth
    case previousMonth
}
