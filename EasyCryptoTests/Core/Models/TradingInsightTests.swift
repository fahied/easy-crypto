//
//  TradingInsightTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given the AI-insight persistence")
@MainActor
struct TradingInsightTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TradingInsight.self, InsightState.self,
            configurations: config
        )
    }

    @Test("When a TradingInsight is inserted, then all fields round-trip")
    func tradingInsightRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(TradingInsight(
            title: "Concentration risk",
            body: "BTC makes up most of your trades.",
            category: "concentration",
            severity: "warning",
            symbol: "BTCUSDT",
            generatedAt: generatedAt
        ))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<TradingInsight>()).first)
        #expect(fetched.title == "Concentration risk")
        #expect(fetched.body == "BTC makes up most of your trades.")
        #expect(fetched.category == "concentration")
        #expect(fetched.severity == "warning")
        #expect(fetched.symbol == "BTCUSDT")
        #expect(fetched.generatedAt == generatedAt)
    }

    @Test("When an InsightState is inserted, then lastGeneratedAt round-trips")
    func insightStateRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generatedAt = Date(timeIntervalSince1970: 1_700_010_000)
        context.insert(InsightState(lastGeneratedAt: generatedAt))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<InsightState>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.lastGeneratedAt == generatedAt)
    }
}
