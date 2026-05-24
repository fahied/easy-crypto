//
//  Kline.swift
//  EasyCrypto
//

import Foundation

nonisolated struct Kline: Equatable, Sendable, Identifiable {
    var id: Int64 { openTime }

    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let closeTime: Int64

    var openDate: Date {
        Date(timeIntervalSince1970: Double(openTime) / 1000.0)
    }

    var closeDate: Date {
        Date(timeIntervalSince1970: Double(closeTime) / 1000.0)
    }
}
