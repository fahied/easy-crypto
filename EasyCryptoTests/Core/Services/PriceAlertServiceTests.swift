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
        lossBaseline: Double = 0,
        percentThreshold: Double = 0,
        referencePrice: Double = 0,
        trades: [FIFOTrade]
    ) -> PriceAlertConfigInput {
        PriceAlertConfigInput(
            symbol: symbol,
            asset: asset,
            isEnabled: isEnabled,
            thresholdUSD: threshold,
            lastNotifiedProfit: baseline,
            lastNotifiedLoss: lossBaseline,
            percentThreshold: percentThreshold,
            referencePrice: referencePrice,
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
        #expect(fired.first?.direction == .gain)
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

    @Test("When the loss drop meets the threshold, then a loss alert fires and advances the loss baseline")
    func firesLossWhenDropMeetsThreshold() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 49800]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // Buy 1 BTC @ 50000; @49800 → unrealized profit -200; drop of 200 from baseline 0.
        let cfg = config(lossBaseline: 0, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.count == 1)
        #expect(fired.first?.direction == .loss)
        #expect(fired.first?.currentProfit == -200)
        #expect(fired.first?.newBaseline == -200)
    }

    @Test("When the loss drop is below the threshold, then it does not fire")
    func doesNotFireLossBelowThreshold() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 49950]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // @49950 → profit -50; drop of 50 (< 100).
        let cfg = config(lossBaseline: 0, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        #expect(fired.isEmpty)
    }

    @Test("When re-evaluated at the advanced loss baseline, then it does not fire again on the same decline")
    func noDoubleFireOnSameLoss() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 49800]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let trades = [buy(1, at: 50000, asset: "BTC")]

        let first = try await service.evaluate([config(lossBaseline: 0, trades: trades)])
        let newLossBaseline = try #require(first.first?.newBaseline)

        let second = try await service.evaluate([config(lossBaseline: newLossBaseline, trades: trades)])

        #expect(second.isEmpty)
    }

    @Test("When the reference price is unset, then it is seeded silently without a price alert")
    func seedsReferenceSilently() async throws {
        var scheduled = false
        let spy = NotificationService(
            requestAuthorization: { true },
            isAuthorized: { true },
            scheduleAlert: { _ in scheduled = true }
        )
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: spy
        )
        let cfg = config(percentThreshold: 5, referencePrice: 0, trades: [])

        let fired = try await service.evaluate([cfg])

        #expect(fired.count == 1)
        #expect(fired.first?.direction == .priceReference)
        #expect(fired.first?.newBaseline == 60000)
        #expect(scheduled == false)
    }

    @Test("When price rises past the percent threshold, then a price-up alert fires and resets the reference")
    func firesPriceUp() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 105000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // reference 100000, +5% threshold, price 105000 = +5%.
        let cfg = config(percentThreshold: 5, referencePrice: 100000, trades: [])

        let fired = try await service.evaluate([cfg])

        #expect(fired.count == 1)
        #expect(fired.first?.direction == .priceUp)
        #expect(fired.first?.newBaseline == 105000)
    }

    @Test("When price falls past the percent threshold, then a price-down alert fires")
    func firesPriceDown() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 94000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // reference 100000, price 94000 = -6% (<= -5%).
        let cfg = config(percentThreshold: 5, referencePrice: 100000, trades: [])

        let fired = try await service.evaluate([cfg])

        #expect(fired.count == 1)
        #expect(fired.first?.direction == .priceDown)
        #expect(fired.first?.newBaseline == 94000)
    }

    @Test("When the price move is below the percent threshold, then no price alert fires")
    func noPriceAlertBelowThreshold() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 103000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        // reference 100000, price 103000 = +3% (< 5%).
        let cfg = config(percentThreshold: 5, referencePrice: 100000, trades: [])

        let fired = try await service.evaluate([cfg])

        #expect(fired.isEmpty)
    }

    @Test("When a gain alert fires, then it carries the delivered notification copy")
    func gainCarriesDeliveredAlert() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let cfg = config(baseline: 9800, trades: [buy(1, at: 50000, asset: "BTC")])

        let fired = try await service.evaluate([cfg])

        let delivered = try #require(fired.first?.deliveredAlert)
        #expect(delivered.title == "BTC profit up")
        #expect(delivered.body == "BTC unrealized P&L is now 10000 USDT.")
    }

    @Test("When the reference price is seeded silently, then no notification copy is carried")
    func silentSeedHasNoDeliveredAlert() async throws {
        let service = PriceAlertService.live(
            priceService: priceService(["BTCUSDT": 60000]),
            fifoCalculator: .live,
            notificationService: .noop
        )
        let cfg = config(percentThreshold: 5, referencePrice: 0, trades: [])

        let fired = try await service.evaluate([cfg])

        #expect(fired.first?.direction == .priceReference)
        #expect(fired.first?.deliveredAlert == nil)
    }
}

private actor AlertRecorder {
    private(set) var alerts: [LocalAlert] = []
    func record(_ alert: LocalAlert) { alerts.append(alert) }
}
