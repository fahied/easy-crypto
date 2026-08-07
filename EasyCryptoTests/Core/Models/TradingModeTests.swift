//
//  TradingModeTests.swift
//  EasyCryptoTests
//
//  Tests for the TradingMode enum — codable round-trip, case iteration, ordering.

import Foundation
import Testing
@testable import EasyCrypto

@Suite("Given the TradingMode enum")
struct TradingModeTests {

    @Test("When encoding and decoding, then round-trips without loss")
    func codableRoundTrip() throws {
        for mode in TradingMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TradingMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("When all cases are iterated, then there are exactly three")
    func caseCount() {
        #expect(TradingMode.allCases.count == 3)
    }

    @Test("When compared, then ordering follows rawValue alphabetically")
    func ordering() {
        #expect(TradingMode.spot < TradingMode.crossMargin)
        #expect(TradingMode.crossMargin < TradingMode.isolatedMargin)
        #expect(TradingMode.spot < TradingMode.isolatedMargin)
    }

    @Test("When raw values are decoded from JSON, then maps correctly")
    func decodeFromJSON() throws {
        let json = """
        { "mode": "cross_margin" }
        """.data(using: .utf8)!

        struct Wrapper: Codable {
            let mode: TradingMode
        }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(decoded.mode == .crossMargin)
    }

    @Test("When displayName is called, then returns human-readable string")
    func displayNames() {
        #expect(TradingMode.spot.displayName == "Spot")
        #expect(TradingMode.crossMargin.displayName == "Cross Margin")
        #expect(TradingMode.isolatedMargin.displayName == "Isolated Margin")
    }
}
