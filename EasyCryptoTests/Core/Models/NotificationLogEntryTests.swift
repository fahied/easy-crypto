//
//  NotificationLogEntryTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given a NotificationLogEntry")
@MainActor
struct NotificationLogEntryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: NotificationLogEntry.self, configurations: config)
    }

    @Test("When inserted, then it round-trips through an in-memory container")
    func roundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = NotificationLogEntry(
            symbol: "BTCUSDT",
            asset: "BTC",
            title: "BTC profit up",
            body: "BTC unrealized P&L is now 10000 USDT.",
            direction: "gain",
            value: 10000,
            firedAt: firedAt
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NotificationLogEntry>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.symbol == "BTCUSDT")
        #expect(stored.asset == "BTC")
        #expect(stored.title == "BTC profit up")
        #expect(stored.body == "BTC unrealized P&L is now 10000 USDT.")
        #expect(stored.direction == "gain")
        #expect(stored.value == 10000)
        #expect(stored.firedAt == firedAt)
    }
}
