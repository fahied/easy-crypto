//
//  CandleDropTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given the CandleDrop rule")
struct CandleDropTests {

    private func kline(close: Double, openTime: Int64) -> Kline {
        Kline(
            openTime: openTime,
            open: close,
            high: close,
            low: close,
            close: close,
            volume: 1,
            closeTime: openTime + 899_999
        )
    }

    @Test("When the last two candles each close lower, then it is a consecutive drop")
    func twoConsecutiveLowerCloses() {
        let candles = [
            kline(close: 100, openTime: 0),
            kline(close: 99, openTime: 900_000),
            kline(close: 98, openTime: 1_800_000),
            kline(close: 97, openTime: 2_700_000),
        ]
        #expect(CandleDrop.isConsecutiveDrop(candles))
    }

    @Test("When prices are rising, then it is not a drop")
    func risingIsNotADrop() {
        let candles = [
            kline(close: 100, openTime: 0),
            kline(close: 101, openTime: 900_000),
            kline(close: 102, openTime: 1_800_000),
        ]
        #expect(CandleDrop.isConsecutiveDrop(candles) == false)
    }

    @Test("When only the most recent candle drops, then it is not a consecutive drop")
    func singleDropIsNotConsecutive() {
        let candles = [
            kline(close: 100, openTime: 0),
            kline(close: 101, openTime: 900_000),
            kline(close: 99, openTime: 1_800_000),
        ]
        #expect(CandleDrop.isConsecutiveDrop(candles) == false)
    }

    @Test("When the latest candle recovers after a drop, then it is not a drop")
    func recoveryIsNotADrop() {
        let candles = [
            kline(close: 100, openTime: 0),
            kline(close: 99, openTime: 900_000),
            kline(close: 100, openTime: 1_800_000),
        ]
        #expect(CandleDrop.isConsecutiveDrop(candles) == false)
    }

    @Test("When there are fewer than three candles, then it is not a drop")
    func tooFewCandles() {
        let candles = [
            kline(close: 100, openTime: 0),
            kline(close: 99, openTime: 900_000),
        ]
        #expect(CandleDrop.isConsecutiveDrop(candles) == false)
    }
}
