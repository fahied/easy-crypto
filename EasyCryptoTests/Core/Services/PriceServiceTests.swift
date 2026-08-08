//
//  PriceServiceTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

// MARK: - Tests

@Suite("Given a live PriceService")
struct LivePriceServiceTests {

    @Test("When fetching prices for symbols, then returns correct price map")
    func fetchPricesMapsCorrectly() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in
                [
                    BinanceTickerPrice(symbol: "BTCUSDT", price: "65000.50"),
                    BinanceTickerPrice(symbol: "ETHUSDT", price: "3500.25"),
                ]
            },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
        let service = PriceService.live(apiClient: apiClient)
        let prices = try await service.fetchPrices(["BTCUSDT", "ETHUSDT"])

        #expect(prices.count == 2)
        #expect(prices["BTCUSDT"] == 65000.50)
        #expect(prices["ETHUSDT"] == 3500.25)
    }

    @Test("When fetching with empty symbols, then returns empty map")
    func emptySymbolsReturnsEmpty() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { symbols in
                Issue.record("Should not call API with empty symbols")
                return []
            },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
        let service = PriceService.live(apiClient: apiClient)
        let prices = try await service.fetchPrices([])

        #expect(prices.isEmpty)
    }

    @Test("When API returns invalid price string, then that symbol is skipped")
    func invalidPriceSkipped() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in
                [
                    BinanceTickerPrice(symbol: "BTCUSDT", price: "65000.00"),
                    BinanceTickerPrice(symbol: "BADUSDT", price: "not_a_number"),
                ]
            },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
        let service = PriceService.live(apiClient: apiClient)
        let prices = try await service.fetchPrices(["BTCUSDT", "BADUSDT"])

        #expect(prices.count == 1)
        #expect(prices["BTCUSDT"] == 65000.00)
        #expect(prices["BADUSDT"] == nil)
    }

    @Test("When API throws, then result degrades to empty rather than propagating")
    func errorDegradesToEmpty() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet)) },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "0", totalAssetOfBtc: "0",
                    totalLiabilityOfBtc: "0", totalNetAssetOfBtc: "0",
                    totalAsset: "0", totalLiability: "0",
                    totalNetAsset: "0", maxBorrowable: "0",
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
        let service = PriceService.live(apiClient: apiClient)

        // Ticker fetch failures degrade to an empty map rather than throwing —
        // a partial price outage shouldn't take down the whole portfolio.
        let prices = try await service.fetchPrices(["BTCUSDT"])
        #expect(prices.isEmpty)
    }
}

@Suite("Given a preview PriceService")
struct PreviewPriceServiceTests {

    @Test("Then it returns sample prices")
    func previewReturnsSampleData() async throws {
        let prices = try await PriceService.preview.fetchPrices([])
        #expect(prices["BTCUSDT"] == 65000.0)
        #expect(prices["ETHUSDT"] == 3500.0)
    }
}

@Suite("Given a noop PriceService")
struct NoopPriceServiceTests {

    @Test("Then it returns empty map")
    func noopReturnsEmpty() async throws {
        let prices = try await PriceService.noop.fetchPrices(["BTCUSDT"])
        #expect(prices.isEmpty)
    }
}
