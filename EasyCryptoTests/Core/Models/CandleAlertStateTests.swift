//
//  CandleAlertStateTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given the candle-alert persistence")
@MainActor
struct CandleAlertStateTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: CandleAlertState.self, PriceAlertConfig.self,
            configurations: config
        )
    }

    @Test("When a CandleAlertState is inserted, then lastCheckedAt round-trips")
    func candleAlertStateRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(CandleAlertState(lastCheckedAt: checkedAt))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CandleAlertState>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.lastCheckedAt == checkedAt)
    }

    @Test("When lastCandleDropOpenTime is set, then it persists on PriceAlertConfig")
    func lastCandleDropOpenTimePersists() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let config = PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true)
        config.lastCandleDropOpenTime = 1_700_002_700_000
        context.insert(config)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(fetched.lastCandleDropOpenTime == 1_700_002_700_000)
    }
}
