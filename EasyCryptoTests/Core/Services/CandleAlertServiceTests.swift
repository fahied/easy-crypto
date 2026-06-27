//
//  CandleAlertServiceTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given a live CandleAlertService")
struct CandleAlertServiceTests {

    // MARK: - Helpers

    /// A past base time so candles count as closed under a real `Date()`.
    private static let base: Int64 = 1_700_000_000_000

    private func kline(close: Double, index: Int64, closeTime: Int64? = nil) -> Kline {
        let openTime = Self.base + index * 900_000
        return Kline(
            openTime: openTime,
            open: close,
            high: close,
            low: close,
            close: close,
            volume: 1,
            closeTime: closeTime ?? (openTime + 899_999)
        )
    }

    private func service(
        klines: [Kline],
        notificationService: NotificationService = .noop,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> CandleAlertService {
        .live(
            fetchKlines: { _, _, _ in klines },
            notificationService: notificationService,
            now: now
        )
    }

    private func input(
        lastCandleDropOpenTime: Int64 = 0,
        isEnabled: Bool = true
    ) -> CandleAlertInput {
        CandleAlertInput(
            symbol: "BTCUSDT",
            asset: "BTC",
            isEnabled: isEnabled,
            lastCandleDropOpenTime: lastCandleDropOpenTime
        )
    }

    // MARK: - Tests

    @Test("When the last two candles drop, then a candle-drop alert fires with the latest openTime")
    func firesOnConsecutiveDrop() async throws {
        let klines = [
            kline(close: 100, index: 0),
            kline(close: 99, index: 1),
            kline(close: 98, index: 2),
            kline(close: 97, index: 3),
        ]
        let svc = service(klines: klines)

        let fired = try await svc.evaluate([input()])

        #expect(fired.count == 1)
        #expect(fired.first?.direction == .candleDrop)
        #expect(fired.first?.newBaseline == Double(Self.base + 3 * 900_000))
        #expect(fired.first?.deliveredAlert != nil)
    }

    @Test("When the latest candle already triggered, then it does not fire again")
    func dedupsOnSameLatestCandle() async throws {
        let klines = [
            kline(close: 100, index: 0),
            kline(close: 99, index: 1),
            kline(close: 98, index: 2),
            kline(close: 97, index: 3),
        ]
        let svc = service(klines: klines)
        let latestOpenTime = Self.base + 3 * 900_000

        let fired = try await svc.evaluate([input(lastCandleDropOpenTime: latestOpenTime)])

        #expect(fired.isEmpty)
    }

    @Test("When the config is disabled, then nothing fires")
    func skipsDisabled() async throws {
        let klines = [
            kline(close: 100, index: 0),
            kline(close: 99, index: 1),
            kline(close: 98, index: 2),
        ]
        let svc = service(klines: klines)

        let fired = try await svc.evaluate([input(isEnabled: false)])

        #expect(fired.isEmpty)
    }

    @Test("When prices are rising, then nothing fires")
    func skipsWhenRising() async throws {
        let klines = [
            kline(close: 100, index: 0),
            kline(close: 101, index: 1),
            kline(close: 102, index: 2),
        ]
        let svc = service(klines: klines)

        let fired = try await svc.evaluate([input()])

        #expect(fired.isEmpty)
    }

    @Test("When the in-progress candle would break the drop, then it is excluded and the alert still fires")
    func excludesInProgressCandle() async throws {
        // now = 2_700_000 ms; candle index 3 closes in the future and is excluded.
        let now = Date(timeIntervalSince1970: 2700)
        let klines = [
            Kline(openTime: 0, open: 100, high: 100, low: 100, close: 100, volume: 1, closeTime: 899_999),
            Kline(openTime: 900_000, open: 99, high: 99, low: 99, close: 99, volume: 1, closeTime: 1_799_999),
            Kline(openTime: 1_800_000, open: 98, high: 98, low: 98, close: 98, volume: 1, closeTime: 2_699_999),
            // In-progress: closeTime in the future, would otherwise break the drop.
            Kline(openTime: 2_700_000, open: 200, high: 200, low: 200, close: 200, volume: 1, closeTime: 3_599_999),
        ]
        let svc = service(klines: klines, now: { now })

        let fired = try await svc.evaluate([input()])

        #expect(fired.count == 1)
        #expect(fired.first?.newBaseline == 1_800_000) // latest *closed* candle
    }
}
