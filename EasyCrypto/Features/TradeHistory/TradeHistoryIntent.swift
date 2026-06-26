//
//  TradeHistoryIntent.swift
//  EasyCrypto
//

import Foundation

enum TradeHistoryIntent: Intent {
    case loadHistory
    case filterByCoin(String?)
    case nextMonth
    case previousMonth
}
