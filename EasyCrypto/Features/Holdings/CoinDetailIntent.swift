//
//  CoinDetailIntent.swift
//  EasyCrypto
//

import Foundation

enum ChartInterval: String, Sendable, CaseIterable {
    case oneHour = "1h"
    case fourHour = "4h"
    case oneDay = "1d"
    case oneWeek = "1w"

    var displayName: String {
        switch self {
        case .oneHour: "1H"
        case .fourHour: "4H"
        case .oneDay: "1D"
        case .oneWeek: "1W"
        }
    }
}

enum CoinDetailIntent: Intent {
    case loadDetail(asset: String)
    case changeChartInterval(ChartInterval)
}
