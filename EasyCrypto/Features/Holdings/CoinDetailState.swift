//
//  CoinDetailState.swift
//  EasyCrypto
//

import Foundation

struct CoinDetailState: ViewState {
    var asset: String = ""
    var holding: Holding?
    var trades: [Trade] = []
    var klines: [Kline] = []
    var chartInterval: ChartInterval = .oneDay
    var isLoading: Bool = false
    var error: String?
}
