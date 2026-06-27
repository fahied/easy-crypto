//
//  CandleAlertRefresherTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given the CandleAlertRefresher")
@MainActor
struct CandleAlertRefresherTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self,
            NotificationLogEntry.self, CandleAlertState.self,
            configurations: config
        )
    }

    /// A past base time so candles count as closed under a real `Date()`.
    private static let base: Int64 = 1_700_000_000_000

    private func droppingKlines() -> [Kline] {
        (0..<4).map { i in
            let openTime = Self.base + Int64(i) * 900_000
            let close = 100.0 - Double(i) // 100, 99, 98, 97
            return Kline(
                openTime: openTime,
                open: close, high: close, low: close, close: close,
                volume: 1, closeTime: openTime + 899_999
            )
        }
    }

    private func candleService() -> CandleAlertService {
        .live(
            fetchKlines: { _, _, _ in self.droppingKlines() },
            notificationService: .noop
        )
    }

    @Test("When checked within the last hour, then it is throttled and nothing changes")
    func throttledWithinHour() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(CandleAlertState(lastCheckedAt: now.addingTimeInterval(-600))) // 10 min ago
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true))
        try context.save()

        try await CandleAlertRefresher.run(modelContext: context, candleService: candleService(), now: now)

        #expect(try context.fetch(FetchDescriptor<NotificationLogEntry>()).isEmpty)
        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastCandleDropOpenTime == 0)
    }

    @Test("When over an hour has passed and candles drop, then it fires, persists, and logs")
    func firesAfterThrottleWindow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(CandleAlertState(lastCheckedAt: now.addingTimeInterval(-7200))) // 2 h ago
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: true))
        try context.save()

        try await CandleAlertRefresher.run(modelContext: context, candleService: candleService(), now: now)

        let config = try #require(try context.fetch(FetchDescriptor<PriceAlertConfig>()).first)
        #expect(config.lastCandleDropOpenTime == Self.base + 3 * 900_000)

        let entries = try context.fetch(FetchDescriptor<NotificationLogEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.direction == "candleDrop")
        #expect(entries.first?.symbol == "BTCUSDT")

        let state = try #require(try context.fetch(FetchDescriptor<CandleAlertState>()).first)
        #expect(state.lastCheckedAt == now)
    }

    @Test("When the only config is disabled, then nothing fires but the check is stamped")
    func skipsDisabledButStamps() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(PriceAlertConfig(symbol: "BTCUSDT", isEnabled: false))
        try context.save()

        try await CandleAlertRefresher.run(modelContext: context, candleService: candleService(), now: now)

        #expect(try context.fetch(FetchDescriptor<NotificationLogEntry>()).isEmpty)
        let state = try #require(try context.fetch(FetchDescriptor<CandleAlertState>()).first)
        #expect(state.lastCheckedAt == now)
    }
}
