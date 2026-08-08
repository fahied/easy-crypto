//
//  MarginBalanceTests.swift
//  EasyCryptoTests
//
//  Tests for MarginBalance SwiftData model — persistence, unique key, netAsset.

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given a MarginBalance SwiftData model")
struct MarginBalanceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MarginBalance.self, configurations: config
        )
    }

    @Test("When created with default values, then all fields are correct")
    func creationWithDefaults() {
        let balance = MarginBalance(
            symbol: "BTCUSDT",
            isolatedMarginKey: "123456",
            asset: "BTC"
        )
        #expect(balance.symbol == "BTCUSDT")
        #expect(balance.isolatedMarginKey == "123456")
        #expect(balance.asset == "BTC")
        #expect(balance.borrowed == 0)
        #expect(balance.free == 0)
        #expect(balance.locked == 0)
        #expect(balance.interest == 0)
        #expect(balance.netAsset == 0)
    }

    @Test("When created with values, then netAsset is computed correctly")
    func netAssetCalculation() {
        let balance = MarginBalance(
            symbol: "ETHUSDT",
            isolatedMarginKey: "789",
            asset: "ETH",
            borrowed: 2.0,
            free: 5.0,
            locked: 1.5,
            interest: 0.1
        )
        #expect(balance.netAsset == 4.4) // 5 + 1.5 - 2.0 - 0.1
    }

    @Test("When inserted into SwiftData, then it persists and can be fetched")
    @MainActor
    func persistenceRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let balance = MarginBalance(
            symbol: "BTCUSDT",
            isolatedMarginKey: "123456",
            asset: "BTC",
            borrowed: 1.0,
            free: 0.5,
            locked: 0.1,
            interest: 0.01
        )
        context.insert(balance)
        try context.save()

        let descriptor = FetchDescriptor<MarginBalance>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        let first = try #require(fetched.first)
        #expect(first.asset == "BTC")
        #expect(first.borrowed == 1.0)
        #expect(abs(first.netAsset - -0.41) < 0.0001)
    }

    @Test("When unique key differs, then both entries persist")
    @MainActor
    func uniqueKeyAllowsMultipleSymbols() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(MarginBalance(
            symbol: "BTCUSDT", isolatedMarginKey: "k1", asset: "BTC",
            free: 1.0
        ))
        context.insert(MarginBalance(
            symbol: "ETHUSDT", isolatedMarginKey: "k1", asset: "ETH",
            free: 10.0
        ))
        try context.save()

        let descriptor = FetchDescriptor<MarginBalance>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 2)
    }
}
