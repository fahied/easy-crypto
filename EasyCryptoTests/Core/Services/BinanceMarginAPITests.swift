//
//  BinanceMarginAPITests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

// MARK: - Given a live BinanceAPIClient with margin closures

@Suite("Given a live BinanceAPIClient with margin closures")
struct LiveMarginAPITests {

    private func makeLiveClient(
        marginAccount: BinanceMarginAccount? = nil,
        isolatedAccount: BinanceIsolatedMarginAccount? = nil,
        marginTrades: [BinanceMarginTrade] = [],
        marginOrders: [BinanceMarginOrder] = [],
        marginAssets: [BinanceMarginAsset] = [],
        marginTransfers: [BinanceMarginTransfer] = []
    ) -> BinanceAPIClient {
        BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                if let account = marginAccount {
                    return account
                }
                return BinanceMarginAccount(
                    marginLevel: "2.0",
                    totalAssetOfBtc: "1.0",
                    totalLiabilityOfBtc: "0.3",
                    totalNetAssetOfBtc: "0.7",
                    totalAsset: "65000",
                    totalLiability: "19500",
                    totalNetAsset: "45500",
                    maxBorrowable: "13000",
                    maintained: "1000",
                    userAssets: [
                        BinanceMarginAccount.AssetEntry(
                            asset: "BTC", borrowed: "0",
                            free: "0.5", locked: "0",
                            interest: "0", netAsset: "0.5",
                            netAssetOfBtc: "0.5", maxBorrowable: "0.5"
                        ),
                        BinanceMarginAccount.AssetEntry(
                            asset: "USDT", borrowed: "5000",
                            free: "10000", locked: "0",
                            interest: "50", netAsset: "4950",
                            netAssetOfBtc: "0.076", maxBorrowable: "10000"
                        ),
                    ]
                )
            },
            fetchIsolatedMarginAccount: { _ in
                if let isolatedAccount {
                    return isolatedAccount
                }
                return BinanceIsolatedMarginAccount(
                    assets: [
                        BinanceIsolatedMarginAccount.IsolatedPair(
                            symbol: "BTCUSDT",
                            marginLevel: "3.2",
                            marginRatio: "0.18",
                            indexPrice: "62000",
                            liquidatePrice: "45230",
                            liquidateRate: "1.0",
                            tradeEnabled: true,
                            enabled: true,
                            baseAsset: BinanceIsolatedMarginAccount.AssetDetail(
                                asset: "BTC", borrowed: "0.1", free: "0.4",
                                locked: "0", interest: "0.001", netAsset: "0.3"
                            ),
                            quoteAsset: BinanceIsolatedMarginAccount.AssetDetail(
                                asset: "USDT", borrowed: "0", free: "500",
                                locked: "0", interest: "0", netAsset: "500"
                            )
                        ),
                    ],
                    totalAssetOfBtc: "0.7",
                    totalLiabilityOfBtc: "0.1",
                    totalNetAssetOfBtc: "0.6"
                )
            },
            fetchMarginMyTrades: { _, _, _ in marginTrades },
            fetchMarginOpenOrders: { _, _ in marginOrders },
            fetchMarginAllAssets: { marginAssets },
            fetchIsolatedMarginTransfers: { _ in marginTransfers }
        )
    }

    // MARK: fetchMarginAccount

    @Test("When fetchMarginAccount succeeds, then returns full account snapshot")
    func fetchMarginAccountReturnsSnapshot() async throws {
        let client = makeLiveClient()
        let account = try await client.fetchMarginAccount()

        #expect(account.marginLevel == "2.0")
        #expect(account.totalAssetOfBtc == "1.0")
        #expect(account.totalLiabilityOfBtc == "0.3")
        #expect(account.totalNetAssetOfBtc == "0.7")
        #expect(account.totalAsset == "65000")
        #expect(account.totalLiability == "19500")
        #expect(account.totalNetAsset == "45500")
        #expect(account.maxBorrowable == "13000")
        #expect(account.maintained == "1000")
        #expect(account.userAssets?.count == 2)
    }

    @Test("When fetchMarginAccount returns assets, then userAssets are populated")
    func marginAccountUserAssetsPopulated() async throws {
        let client = makeLiveClient()
        let account = try await client.fetchMarginAccount()

        let btc = try #require(account.userAssets?.first { $0.asset == "BTC" })
        #expect(btc.borrowed == "0")
        #expect(btc.free == "0.5")
        #expect(btc.locked == "0")
        #expect(btc.interest == "0")

        let usdt = try #require(account.userAssets?.first { $0.asset == "USDT" })
        #expect(usdt.borrowed == "5000")
        #expect(usdt.free == "10000")
        #expect(usdt.locked == "0")
        #expect(usdt.interest == "50")
    }

    // MARK: fetchIsolatedMarginAccount

    @Test("When fetchIsolatedMarginAccount succeeds, then returns liquidation price and margin level per symbol")
    func fetchIsolatedMarginAccountReturnsSnapshot() async throws {
        let client = makeLiveClient()
        let account = try await client.fetchIsolatedMarginAccount(["BTCUSDT"])

        #expect(account.assets.count == 1)
        let pair = try #require(account.assets.first { $0.symbol == "BTCUSDT" })
        #expect(pair.liquidatePrice == "45230")
        #expect(pair.marginLevel == "3.2")
        #expect(pair.baseAsset.asset == "BTC")
        #expect(pair.baseAsset.borrowed == "0.1")
        #expect(pair.quoteAsset.asset == "USDT")
    }

    // MARK: fetchMarginMyTrades

    @Test("When fetchMarginMyTrades succeeds, then returns margin trades")
    func fetchMarginMyTradesReturnsTrades() async throws {
        let trades: [BinanceMarginTrade] = [
            BinanceMarginTrade(
                id: 1, symbol: "BTCUSDT", price: "50000", qty: "0.1",
                quoteQty: "5000", commission: "0.001", commissionAsset: "BTC",
                time: 1_700_000_000_000, isBuyer: true, orderId: 100,
                isIsolated: false, marginBuyBorrowAmount: nil, marginBuyBorrowAsset: nil
            ),
        ]
        let client = makeLiveClient(marginTrades: trades)
        let result = try await client.fetchMarginMyTrades("BTCUSDT", nil, false)

        #expect(result.count == 1)
        #expect(result[0].id == 1)
        #expect(result[0].symbol == "BTCUSDT")
        #expect(result[0].isIsolated == false)
        #expect(result[0].marginBuyBorrowAmount == nil)
    }

    @Test("When fetchMarginMyTrades is called with isIsolated=true, then isIsolated is set on trades")
    func fetchMarginMyTradesWithIsolatedFlag() async throws {
        let trades: [BinanceMarginTrade] = [
            BinanceMarginTrade(
                id: 2, symbol: "ETHUSDT", price: "3000", qty: "1.0",
                quoteQty: "3000", commission: "0.001", commissionAsset: "ETH",
                time: 1_700_100_000_000, isBuyer: false, orderId: 200,
                isIsolated: true, marginBuyBorrowAmount: "100", marginBuyBorrowAsset: "USDT"
            ),
        ]
        let client = makeLiveClient(marginTrades: trades)
        let result = try await client.fetchMarginMyTrades("ETHUSDT", 100, true)

        #expect(result.count == 1)
        #expect(result[0].isIsolated == true)
        #expect(result[0].marginBuyBorrowAmount == "100")
        #expect(result[0].marginBuyBorrowAsset == "USDT")
    }

    // MARK: fetchMarginOpenOrders

    @Test("When fetchMarginOpenOrders succeeds, then returns margin orders")
    func fetchMarginOpenOrdersReturnsOrders() async throws {
        let orders: [BinanceMarginOrder] = [
            BinanceMarginOrder(
                symbol: "BTCUSDT", orderId: 500, clientOrderId: "abc123",
                price: "48000", origQty: "0.1", executedQty: "0",
                cummulativeQuoteQty: "0", status: "NEW",
                timeInForce: "GTC", type: "LIMIT", side: "BUY",
                stopPrice: "0", icebergQty: "0", time: 1_700_000_000_000,
                updateTime: 1_700_000_000_000, isIsolated: false
            ),
        ]
        let client = makeLiveClient(marginOrders: orders)
        let result = try await client.fetchMarginOpenOrders("BTCUSDT", false)

        #expect(result.count == 1)
        #expect(result[0].symbol == "BTCUSDT")
        #expect(result[0].orderId == 500)
        #expect(result[0].status == "NEW")
        #expect(result[0].isIsolated == false)
    }

    // MARK: fetchMarginAllAssets

    @Test("When fetchMarginAllAssets succeeds, then returns assets with borrowed/free/locked")
    func fetchMarginAllAssetsReturnsAssets() async throws {
        let assets: [BinanceMarginAsset] = [
            BinanceMarginAsset(
                asset: "BTC", borrowed: "0.1", free: "0.4",
                locked: "0", netAsset: "0.3", maxBorrowable: "0.5", maintained: nil
            ),
            BinanceMarginAsset(
                asset: "USDT", borrowed: "1000", free: "5000",
                locked: "200", netAsset: "4200", maxBorrowable: "10000", maintained: "500"
            ),
        ]
        let client = makeLiveClient(marginAssets: assets)
        let result = try await client.fetchMarginAllAssets()

        #expect(result.count == 2)
        let btc = try #require(result.first { $0.asset == "BTC" })
        #expect(btc.borrowed == "0.1")
        #expect(btc.free == "0.4")
        #expect(btc.locked == "0")
        #expect(btc.netAsset == "0.3")
        let usdt = try #require(result.first { $0.asset == "USDT" })
        #expect(usdt.borrowed == "1000")
        #expect(usdt.free == "5000")
        #expect(usdt.locked == "200")
    }

    // MARK: fetchIsolatedMarginTransfers

    @Test("When fetchIsolatedMarginTransfers succeeds, then returns transfer history")
    func fetchIsolatedMarginTransfersReturnsHistory() async throws {
        let transfers: [BinanceMarginTransfer] = [
            BinanceMarginTransfer(
                asset: "USDT", symbol: "BTCUSDT", transferType: "1",
                amount: "1000", timestamp: 1_700_000_000_000,
                status: "SUCCESS", tranId: 1
            ),
            BinanceMarginTransfer(
                asset: "USDT", symbol: "BTCUSDT", transferType: "2",
                amount: "500", timestamp: 1_700_050_000_000,
                status: "SUCCESS", tranId: 2
            ),
        ]
        let client = makeLiveClient(marginTransfers: transfers)
        let result = try await client.fetchIsolatedMarginTransfers("BTCUSDT")

        #expect(result.count == 2)
        #expect(result[0].asset == "USDT")
        #expect(result[0].symbol == "BTCUSDT")
        #expect(result[0].amount == "1000")
        #expect(result[0].tranId == 1)
    }

    // MARK: Error propagation

    @Test("When fetchMarginAccount throws, then error propagates")
    func marginAccountErrorPropagates() async {
        let client = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet))
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        do {
            _ = try await client.fetchMarginAccount()
            Issue.record("Expected error to propagate")
        } catch let error as BinanceError {
            if case .networkError = error {
                // expected
            } else {
                Issue.record("Expected networkError but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("When fetchIsolatedMarginAccount throws, then error propagates")
    func isolatedMarginAccountErrorPropagates() async {
        let client = BinanceAPIClient(
            fetchAccount: { [] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
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
            fetchIsolatedMarginAccount: { _ in
                throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet))
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        do {
            _ = try await client.fetchIsolatedMarginAccount(["BTCUSDT"])
            Issue.record("Expected error to propagate")
        } catch let error as BinanceError {
            if case .networkError = error {
                // expected
            } else {
                Issue.record("Expected networkError but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Given a preview BinanceAPIClient

@Suite("Given a preview BinanceAPIClient")
struct PreviewMarginAPITests {

    @Test("Then fetchMarginAccount returns sample data")
    func previewFetchMarginAccount() async throws {
        let account = try await BinanceAPIClient.preview.fetchMarginAccount()
        #expect(account.marginLevel == "1.5")
        #expect(account.userAssets?.count == 1)
        #expect(account.userAssets?.first?.asset == "BTC")
    }

    @Test("Then fetchIsolatedMarginAccount returns sample data with a liquidation price")
    func previewFetchIsolatedMarginAccount() async throws {
        let account = try await BinanceAPIClient.preview.fetchIsolatedMarginAccount(["BTCUSDT"])
        #expect(account.assets.count == 1)
        #expect(account.assets.first?.symbol == "BTCUSDT")
        #expect(account.assets.first?.liquidatePrice == "45230")
    }

    @Test("Then fetchMarginMyTrades returns sample data")
    func previewFetchMarginMyTrades() async throws {
        let trades = try await BinanceAPIClient.preview.fetchMarginMyTrades("BTCUSDT", nil, false)
        #expect(trades.count == 1)
        #expect(trades[0].isIsolated == false)
    }

    @Test("Then fetchMarginOpenOrders returns empty")
    func previewFetchMarginOpenOrders() async throws {
        let orders = try await BinanceAPIClient.preview.fetchMarginOpenOrders("BTCUSDT", false)
        #expect(orders.isEmpty)
    }

    @Test("Then fetchMarginAllAssets returns sample data")
    func previewFetchMarginAllAssets() async throws {
        let assets = try await BinanceAPIClient.preview.fetchMarginAllAssets()
        #expect(assets.count == 1)
        #expect(assets.first?.asset == "BTC")
        #expect(assets.first?.borrowed == "0")
    }

    @Test("Then fetchIsolatedMarginTransfers returns sample data")
    func previewFetchIsolatedMarginTransfers() async throws {
        let transfers = try await BinanceAPIClient.preview.fetchIsolatedMarginTransfers("BTCUSDT")
        #expect(transfers.count == 1)
        #expect(transfers.first?.tranId == 1)
    }
}

// MARK: - Given a noop BinanceAPIClient

@Suite("Given a noop BinanceAPIClient")
struct NoopMarginAPITests {

    @Test("Then fetchMarginAccount returns zeroed account")
    func noopFetchMarginAccount() async throws {
        let account = try await BinanceAPIClient.noop.fetchMarginAccount()
        #expect(account.marginLevel == "0")
        #expect(account.userAssets?.isEmpty == true)
    }

    @Test("Then fetchIsolatedMarginAccount returns empty")
    func noopFetchIsolatedMarginAccount() async throws {
        let account = try await BinanceAPIClient.noop.fetchIsolatedMarginAccount(["BTCUSDT"])
        #expect(account.assets.isEmpty)
    }

    @Test("Then fetchMarginMyTrades returns empty")
    func noopFetchMarginMyTrades() async throws {
        let trades = try await BinanceAPIClient.noop.fetchMarginMyTrades("BTCUSDT", nil, true)
        #expect(trades.isEmpty)
    }

    @Test("Then fetchMarginOpenOrders returns empty")
    func noopFetchMarginOpenOrders() async throws {
        let orders = try await BinanceAPIClient.noop.fetchMarginOpenOrders("ETHUSDT", true)
        #expect(orders.isEmpty)
    }

    @Test("Then fetchMarginAllAssets returns empty")
    func noopFetchMarginAllAssets() async throws {
        let assets = try await BinanceAPIClient.noop.fetchMarginAllAssets()
        #expect(assets.isEmpty)
    }

    @Test("Then fetchIsolatedMarginTransfers returns empty")
    func noopFetchIsolatedMarginTransfers() async throws {
        let transfers = try await BinanceAPIClient.noop.fetchIsolatedMarginTransfers("ETHUSDT")
        #expect(transfers.isEmpty)
    }
}
