//
//  TradeModelTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given a Trade SwiftData model")
struct TradeModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
    }

    @Test("When created with valid fields, then all properties are set correctly")
    func creationWithValidFields() throws {
        let trade = Trade(
            binanceTradeId: 123456,
            symbol: "BTCUSDT",
            asset: "BTC",
            price: 67500.0,
            quantity: 0.5,
            quoteQuantity: 33750.0,
            commission: 0.0005,
            commissionAsset: "BTC",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            isBuyer: true,
            orderId: 789
        )

        #expect(trade.binanceTradeId == 123456)
        #expect(trade.symbol == "BTCUSDT")
        #expect(trade.asset == "BTC")
        #expect(trade.price == 67500.0)
        #expect(trade.quantity == 0.5)
        #expect(trade.quoteQuantity == 33750.0)
        #expect(trade.commission == 0.0005)
        #expect(trade.commissionAsset == "BTC")
        #expect(trade.isBuyer == true)
        #expect(trade.orderId == 789)
    }

    @Test("When inserted into SwiftData, then it persists and can be fetched")
    @MainActor
    func persistenceRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let trade = Trade(
            binanceTradeId: 100,
            symbol: "ETHUSDT",
            asset: "ETH",
            price: 3500.0,
            quantity: 2.0,
            quoteQuantity: 7000.0,
            commission: 0.002,
            commissionAsset: "ETH",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            isBuyer: true,
            orderId: 200
        )
        context.insert(trade)
        try context.save()

        let descriptor = FetchDescriptor<Trade>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        let first = try #require(fetched.first)
        #expect(first.binanceTradeId == 100)
        #expect(first.symbol == "ETHUSDT")
        #expect(first.asset == "ETH")
        #expect(first.price == 3500.0)
    }

    @Test("When multiple trades are inserted, then they can be fetched by symbol")
    @MainActor
    func fetchBySymbol() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let btcTrade = Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 0.1, quoteQuantity: 6000,
            commission: 0.0001, commissionAsset: "BTC",
            timestamp: Date(), isBuyer: true, orderId: 10
        )
        let ethTrade = Trade(
            binanceTradeId: 2, symbol: "ETHUSDT", asset: "ETH",
            price: 3000, quantity: 1.0, quoteQuantity: 3000,
            commission: 0.001, commissionAsset: "ETH",
            timestamp: Date(), isBuyer: true, orderId: 11
        )
        context.insert(btcTrade)
        context.insert(ethTrade)
        try context.save()

        let symbol = "BTCUSDT"
        let descriptor = FetchDescriptor<Trade>(
            predicate: #Predicate<Trade> { $0.symbol == symbol }
        )
        let btcTrades = try context.fetch(descriptor)
        #expect(btcTrades.count == 1)
        #expect(btcTrades.first?.asset == "BTC")
    }

    @Test("When a sell trade is created, then isBuyer is false")
    func sellTrade() {
        let trade = Trade(
            binanceTradeId: 999, symbol: "BTCUSDT", asset: "BTC",
            price: 70000, quantity: 0.25, quoteQuantity: 17500,
            commission: 0.00025, commissionAsset: "BTC",
            timestamp: Date(), isBuyer: false, orderId: 500
        )
        #expect(trade.isBuyer == false)
    }

    @Test("When fetched with sort by timestamp, then trades are ordered chronologically")
    @MainActor
    func sortByTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let older = Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 0.1, quoteQuantity: 5000,
            commission: 0.0001, commissionAsset: "BTC",
            timestamp: Date(timeIntervalSince1970: 1000), isBuyer: true, orderId: 1
        )
        let newer = Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 0.2, quoteQuantity: 12000,
            commission: 0.0002, commissionAsset: "BTC",
            timestamp: Date(timeIntervalSince1970: 2000), isBuyer: true, orderId: 2
        )
        context.insert(newer)
        context.insert(older)
        try context.save()

        var descriptor = FetchDescriptor<Trade>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 10
        let sorted = try context.fetch(descriptor)

        #expect(sorted.count == 2)
        #expect(sorted[0].binanceTradeId == 1)
        #expect(sorted[1].binanceTradeId == 2)
    }
}
