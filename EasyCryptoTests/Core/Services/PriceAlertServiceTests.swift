//
//  PriceAlertServiceTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given a live PriceAlertService")
struct PriceAlertServiceTests {

    // MARK: - Helpers

    private func buy(_ quantity: Double, at price: Double, asset: String) -> FIFOTrade {
        FIFOTrade(
            price: price,
            quantity: quantity,
            commission: 0,
            commissionAsset: "USDT",
            asset: asset,
            isBuyer: true
        )
    }

    private func priceService(_ map: [String: Double]) -> PriceService {
        PriceService(fetchPrices: { _ in map })
    }

    private func config(
        symbol: String = "BTCUSDT",
        asset: String = "BTC",
        isEnabled: Bool = true,
        threshold: Double = 100,
        baseline: Double = 0,
        trades: [FIFOTrade]
    ) -> PriceAlertConfigInput {
        PriceAlertConfigInput(
            symbol: symbol,
            asset: asset,
            isEnabled: isEnabled,
            thresholdUSD: threshold,
            lastNotifiedProfit: baseline,
            trades: trades
        )
    }

    // MARK: - Tests

    @Test("When the profit increase meets the threshold, then it fires and advances the baseline to current profit")
    func firesWhenThresholdMet() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // Buy 1 BTC @ 50000 (invested 50000); @60000 → unrealized profit 10000.
        let cfg = config(baseline: 9800, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.count == 1)
        #expect(fired.first?.symbol == "BTCUSDT")
        #expect(fired.first?.currentProfit == 10000)
        #expect(fired.first?.newBaseline == 10000)
    }

    @Test("When the profit increase is below the threshold, then it does not fire")
    func doesNotFireBelowThreshold() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // Increase since baseline is only 50 (< 100).
        let cfg = config(baseline: 9950, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.isEmpty)
    }

    @Test("When a config is disabled, then it never fires")
    func skipsDisabledConfigs() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let cfg = config(isEnabled: false, baseline: 0, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.isEmpty)
    }

    @Test("When re-evaluated at the advanced baseline, then it does not fire again on the same gain")
    func noDoubleFireOnSameGain() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let trades = [buy(1, at: 50000, asset: "BTC")]

        let first = try await service.evaluate([config(baseline: 0, trades: trades)])
        let newBaseline = try #require(first.first?.newBaseline)

        let second = try await service.evaluate([config(baseline: newBaseline, trades: trades)])

        #expect(second.isEmpty)
    }

    @Test("When alerts fire, then the notification service receives one alert per fired symbol")
    func deliversNotifications() async throws {
        let recorder = AlertRecorder()
        let spy = NotificationService(
            requestAuthorization: { true },
            isAuthorized: { true },
            scheduleAlert: { await recorder.record($0) }
        )
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000, "ETHUSDT": 4000]),
            fifoCalculator: .live,
            notificationService: spy
        )
        let configs = [
            config(symbol: "BTCUSDT", asset: "BTC", baseline: 0, trades: [buy(1, at: 50000, asset: "BTC")]),
            config(symbol: "ETHUSDT", asset: "ETH", baseline: 0, trades: [buy(1, at: 3000, asset: "ETH")]),
        ]

        let fired = try await service.evaluate(configs)

        #expect(fired.count == 2)
        let recorded = await recorder.alerts
        #expect(recorded.count == 2)
    }

    @Test("When no configs are enabled, then prices are not fetched")
    func skipsPriceFetchWhenNothingEnabled() async throws {
        let service = PriceAlertService.live(
            priceService: PriceService(fetchPrices: { _ in
                Issue.record("Should not fetch prices when no alerts are enabled")
                return [:]
            }),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let cfg = config(isEnabled: false, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.isEmpty)
    }
}

private actor AlertRecorder {
    private(set) var alerts: [LocalAlert] = []
    func record(_ alert: LocalAlert) { alerts.append(alert) }
}
