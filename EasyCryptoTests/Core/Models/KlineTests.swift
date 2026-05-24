//
//  KlineTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
@testable import EasyCrypto

@Suite("Given a Kline value type")
struct KlineTests {

    @Test("When created with valid OHLCV data, then all properties are set")
    func creationWithValidData() {
        let kline = Kline(
            openTime: 1700000000000,
            open: 67000.0,
            high: 68500.0,
            low: 66500.0,
            close: 68000.0,
            volume: 1234.56,
            closeTime: 1700003600000
        )

        #expect(kline.openTime == 1700000000000)
        #expect(kline.open == 67000.0)
        #expect(kline.high == 68500.0)
        #expect(kline.low == 66500.0)
        #expect(kline.close == 68000.0)
        #expect(kline.volume == 1234.56)
        #expect(kline.closeTime == 1700003600000)
    }

    @Test("When close is higher than open, then the candle is bullish")
    func bullishCandle() {
        let kline = Kline(
            openTime: 0, open: 100.0, high: 110.0,
            low: 95.0, close: 108.0, volume: 500.0, closeTime: 0
        )
        #expect(kline.close > kline.open)
    }

    @Test("When close is lower than open, then the candle is bearish")
    func bearishCandle() {
        let kline = Kline(
            openTime: 0, open: 100.0, high: 105.0,
            low: 90.0, close: 92.0, volume: 500.0, closeTime: 0
        )
        #expect(kline.close < kline.open)
    }

    @Test("When two klines have same data, then they are equal")
    func equatable() {
        let a = Kline(openTime: 1, open: 10, high: 20, low: 5, close: 15, volume: 100, closeTime: 2)
        let b = Kline(openTime: 1, open: 10, high: 20, low: 5, close: 15, volume: 100, closeTime: 2)
        #expect(a == b)
    }

    @Test("When computing openDate, then it converts milliseconds to Date correctly")
    func openDate() {
        let kline = Kline(
            openTime: 1700000000000, open: 0, high: 0,
            low: 0, close: 0, volume: 0, closeTime: 0
        )
        let expectedDate = Date(timeIntervalSince1970: 1700000000)
        #expect(kline.openDate == expectedDate)
    }
}
