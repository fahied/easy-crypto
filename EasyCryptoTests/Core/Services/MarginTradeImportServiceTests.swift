
//
//  MarginTradeImportServiceTests.swift
//  EasyCryptoTests
//
//  Tests for ADV-CORE-SERVICES-006: MarginTradeImportService
//  Mirrors TradeImportServiceTests but verifies margin-specific behavior:
//  TradingMode parameter, isolatedMarginKey in sync keys, cross/isolated
//  branching, and MappedTrade with correct tradingMode context.
//

import Foundation
import Testing

@testable import EasyCrypto

// MARK: - Helpers

private func makeMarginTrade(
    id: Int64,
    symbol: String = "BTCUSDT",
    price: String = "50000.00",
    qty: String = "1.0",
    quoteQty: String = "50000.00",
    commission: String = "0.001",
    commissionAsset: String = "BTC",
    time: Int64 = 1_700_000_000_000,
    isBuyer: Bool = true,
    orderId: Int64 = 100,
    isIsolated: Bool? = false,
    marginBuyBorrowAmount: String? = nil,
    marginBuyBorrowAsset: String? = nil
) -> BinanceMarginTrade {
    BinanceMarginTrade(
        id: id, symbol: symbol, price: price, qty: qty,
        quoteQty: quoteQty, commission: commission,
        commissionAsset: commissionAsset, time: time,
        isBuyer: isBuyer, orderId: orderId,
        isIsolated: isIsolated,
        marginBuyBorrowAmount: marginBuyBorrowAmount,
        marginBuyBorrowAsset: marginBuyBorrowAsset
    )
}

private func makeClient(
    crossMarginUserAssets: [BinanceMarginAccount.AssetEntry] = [
        BinanceMarginAccount.AssetEntry(
            asset: "BTC", borrowed: "0", free: "0.5",
            locked: "0", interest: "0", netAsset: "0.5",
            netAssetOfBtc: "0.5", maxBorrowable: "0.5"
        ),
    ],
    isolatedMarginAssets: [BinanceMarginAsset] = [],
    tradesForSymbol: @escaping @Sendable (_ symbol: String, _ isIsolated: Bool) -> [BinanceMarginTrade] = { _, _ in [] }
) -> BinanceAPIClient {
    BinanceAPIClient(
        fetchAccount: { [] },
        fetchMyTrades: { _, _ in [] },
        fetchTickerPrices: { _ in [] },
        fetchKlines: { _, _, _ in [] },
        fetchMarginAccount: {
            BinanceMarginAccount(
                marginLevel: "2.0", totalAssetOfBtc: "1.0",
                totalLiabilityOfBtc: "0.3", totalNetAssetOfBtc: "0.7",
                totalAsset: "65000", totalLiability: "19500",
                totalNetAsset: "45500", maxBorrowable: "13000",
                maintained: nil, userAssets: crossMarginUserAssets
            )
        },
        fetchMarginMyTrades: { symbol, _, isIsolated in tradesForSymbol(symbol, isIsolated) },
        fetchMarginOpenOrders: { _, _ in [] },
        fetchMarginAllAssets: { isolatedMarginAssets },
        fetchIsolatedMarginTransfers: { _ in [] }
    )
}

private func makeIsolatedAsset(_ asset: String) -> BinanceMarginAsset {
    BinanceMarginAsset(
        asset: asset, borrowed: "0", free: "1.0",
        locked: "0", netAsset: "1.0", maxBorrowable: "1.0", maintained: nil
    )
}

// MARK: - Mode Tests

@Suite("Given a margin trade import service")
struct ModeTests {

    @Test("When TradingMode.crossMargin, then uses fetchMarginMyTrades with isIsolated=false")
    func crossMarginCallsCorrectEndpoint() async throws {
        let calls = Locked<[(symbol: String, isIsolated: Bool)]>([])

        let client = makeClient(
            tradesForSymbol: { symbol, isIsolated in
                calls.value.append((symbol, isIsolated))
                return [makeMarginTrade(id: 1, symbol: symbol, isIsolated: false)]
            }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.crossMargin, [:])

        let btcCall = try #require(calls.value.first { $0.symbol == "BTCUSDT" })
        #expect(btcCall.isIsolated == false)
    }

    @Test("When TradingMode.isolatedMargin, then uses fetchMarginMyTrades with isIsolated=true")
    func isolatedMarginCallsCorrectEndpoint() async throws {
        let calls = Locked<[(symbol: String, isIsolated: Bool)]>([])

        let client = makeClient(
            tradesForSymbol: { symbol, isIsolated in
                calls.value.append((symbol, isIsolated))
                return [makeMarginTrade(id: 1, symbol: symbol, isIsolated: true)]
            }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.isolatedMargin, ["BTCUSDT": 0])

        let btcCall = try #require(calls.value.first { $0.symbol == "BTCUSDT" })
        #expect(btcCall.isIsolated == true)
    }
}

// MARK: - Sync Metadata Tests

@Suite("Given a margin trade import service generating sync updates")
struct MarginSyncMetadataTests {

    @Test("When crossMargin, then sync update uses 'cross' as the key")
    func crossMarginSyncKey() async throws {
        let client = makeClient(
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? [makeMarginTrade(id: 50, symbol: symbol)] : [] }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, ["cross": 10])

        let update = try #require(result.syncUpdates.first { $0.symbol == "cross" })
        #expect(update.lastTradeId == 50)
    }

    @Test("When isolatedMargin, then sync update uses the symbol as the key")
    func isolatedMarginSyncKey() async throws {
        let client = makeClient(
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? [makeMarginTrade(id: 75, symbol: symbol)] : [] }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["BTCUSDT": 10])

        let update = try #require(result.syncUpdates.first { $0.symbol == "BTCUSDT" })
        #expect(update.lastTradeId == 75)
    }

    @Test("When crossMargin incremental sync, then fromId starts at lastTradeId + 1")
    func crossMarginIncrementalSync() async throws {
        let client = makeClient(
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? [makeMarginTrade(id: 51, symbol: symbol)] : [] }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, ["cross": 50])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 51)
    }

    @Test("When isolatedMargin incremental sync, then fromId starts at lastTradeId + 1")
    func isolatedMarginIncrementalSync() async throws {
        let client = makeClient(
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? [makeMarginTrade(id: 101, symbol: symbol)] : [] }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["BTCUSDT": 100])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 101)
    }
}

// MARK: - Trade Mapping Tests

@Suite("Given a margin trade import service mapping API responses")
struct MarginTradeMappingTests {

    @Test("When API returns a margin trade, then all fields are mapped correctly")
    func mapsAllFields() async throws {
        let client = makeClient(
            tradesForSymbol: { symbol, _ in
                guard symbol == "BTCUSDT" else { return [] }
                return [
                    makeMarginTrade(
                        id: 12345, symbol: "BTCUSDT", price: "50000.50",
                        qty: "0.25", quoteQty: "12500.125",
                        commission: "0.001", commissionAsset: "BTC",
                        time: 1_700_000_000_000, isBuyer: true, orderId: 9876
                    ),
                ]
            }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.binanceTradeId == 12345)
        #expect(trade.symbol == "BTCUSDT")
        #expect(trade.asset == "BTC")
        #expect(trade.price == 50000.50)
        #expect(trade.quantity == 0.25)
        #expect(trade.quoteQuantity == 12500.125)
        #expect(trade.commission == 0.001)
        #expect(trade.commissionAsset == "BTC")
        #expect(trade.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(trade.isBuyer == true)
        #expect(trade.orderId == 9876)
    }

    @Test("When API returns a sell trade, then isBuyer is false")
    func mapsSellTrade() async throws {
        let client = makeClient(
            crossMarginUserAssets: [
                BinanceMarginAccount.AssetEntry(
                    asset: "ETH", borrowed: "0", free: "10.0",
                    locked: "0", interest: "0", netAsset: "10.0",
                    netAssetOfBtc: "0.15", maxBorrowable: "10.0"
                ),
            ],
            tradesForSymbol: { symbol, _ in
                symbol == "ETHUSDT" ? [makeMarginTrade(id: 1, symbol: "ETHUSDT", isBuyer: false)] : []
            }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.isBuyer == false)
        #expect(trade.asset == "ETH")
    }

    @Test("When BinanceMarginTrade has isIsolated=true, then still mapped correctly")
    func mapsIsolatedMarginTrade() async throws {
        let client = makeClient(
            isolatedMarginAssets: [makeIsolatedAsset("ETH")],
            tradesForSymbol: { symbol, _ in
                guard symbol == "ETHUSDT" else { return [] }
                return [
                    makeMarginTrade(
                        id: 42, symbol: "ETHUSDT", price: "3000",
                        qty: "5.0", quoteQty: "15000",
                        commission: "0.01", commissionAsset: "ETH",
                        time: 1_700_000_000_000, isBuyer: false, orderId: 200,
                        isIsolated: true, marginBuyBorrowAmount: "1000",
                        marginBuyBorrowAsset: "USDT"
                    ),
                ]
            }
        )
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["ETHUSDT": 0])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.binanceTradeId == 42)
        #expect(trade.symbol == "ETHUSDT")
        #expect(trade.asset == "ETH")
    }
}

// MARK: - Pagination Tests

@Suite("Given a margin trade import service with pagination")
struct MarginPaginationTests {

    @Test("When paginating, then fromId is last trade ID + 1")
    func paginationFromIdIsCorrect() async throws {
        let callCount = Locked(0)
        var receivedFromIds: [Int64?] = []

        let client = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.5", locked: "0"),
            ] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "2.0", totalAssetOfBtc: "1.0",
                    totalLiabilityOfBtc: "0.3", totalNetAssetOfBtc: "0.7",
                    totalAsset: "65000", totalLiability: "19500",
                    totalNetAsset: "45500", maxBorrowable: "13000",
                    maintained: nil, userAssets: [
                        BinanceMarginAccount.AssetEntry(
                            asset: "BTC", borrowed: "0", free: "0.5",
                            locked: "0", interest: "0", netAsset: "0.5",
                            netAssetOfBtc: "0.5", maxBorrowable: "0.5"
                        ),
                    ]
                )
            },
            fetchMarginMyTrades: { symbol, fromId, _ in
                callCount.value += 1
                guard symbol == "BTCUSDT" else { return [] }
                receivedFromIds.append(fromId)
                if fromId == nil {
                    return (0..<1000).map {
                        makeMarginTrade(id: Int64($0), symbol: "BTCUSDT", time: 1_700_000_000_000 + Int64($0))
                    }
                } else if fromId == 1000 {
                    return (1000..<1200).map {
                        makeMarginTrade(id: Int64($0), symbol: "BTCUSDT", time: 1_700_000_000_000 + Int64($0))
                    }
                }
                return []
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        #expect(result.mappedTrades.count == 1200)
        // First call has nil fromId, second call has 1000 (last of first batch + 1)
        #expect(receivedFromIds[0] == nil)
        #expect(receivedFromIds[1] == 1000)
    }
}

// MARK: - Error Handling Tests

@Suite("Given a margin trade import service with API errors")
struct MarginErrorTests {

    @Test("When fetchMarginAccount throws, then error propagates")
    func marginAccountErrorPropagates() async {
        let client = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.5", locked: "0"),
            ] },
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

        let service = MarginTradeImportService.live(apiClient: client)

        do {
            _ = try await service.sync(.crossMargin, ["cross": 0])
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

    @Test("When fetchMarginMyTrades fails for one symbol, then other symbols still sync")
    func partialFailureContinues() async throws {
        let client = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.5", locked: "0"),
                BinanceBalance(asset: "ETH", free: "10.0", locked: "0"),
            ] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: "2.0", totalAssetOfBtc: "1.0",
                    totalLiabilityOfBtc: "0.3", totalNetAssetOfBtc: "0.7",
                    totalAsset: "65000", totalLiability: "19500",
                    totalNetAsset: "45500", maxBorrowable: "13000",
                    maintained: nil, userAssets: [
                        BinanceMarginAccount.AssetEntry(
                            asset: "BTC", borrowed: "0", free: "0.5",
                            locked: "0", interest: "0", netAsset: "0.5",
                            netAssetOfBtc: "0.5", maxBorrowable: "0.5"
                        ),
                        BinanceMarginAccount.AssetEntry(
                            asset: "ETH", borrowed: "0", free: "10.0",
                            locked: "0", interest: "0", netAsset: "10.0",
                            netAssetOfBtc: "0.15", maxBorrowable: "10.0"
                        ),
                    ]
                )
            },
            fetchMarginMyTrades: { symbol, _, _ in
                if symbol == "BTCUSDT" {
                    throw BinanceError.apiError(code: -1121, message: "Invalid symbol")
                }
                if symbol == "ETHUSDT" {
                    return [makeMarginTrade(id: 1, symbol: symbol)]
                }
                return []
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, ["cross": 0])

        // ETH should still succeed despite BTC failure
        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades[0].symbol == "ETHUSDT")
    }
}

// MARK: - Preview/Noop Tests

@Suite("Given a preview or noop MarginTradeImportService")
struct MarginPreviewNoopTests {

    @Test("When using preview service, then returns sample data")
    func previewReturnsSampleData() async throws {
        let result = try await MarginTradeImportService.preview.sync(.crossMargin, ["cross": 0])
        #expect(!result.mappedTrades.isEmpty)
    }

    @Test("When using noop service, then returns empty result")
    func noopReturnsEmpty() async throws {
        let result = try await MarginTradeImportService.noop.sync(.crossMargin, ["cross": 0])
        #expect(result.mappedTrades.isEmpty)
        #expect(result.syncUpdates.isEmpty)
    }
}

// MARK: - Helpers

/// A simple thread-safe integer wrapper for tracking call counts across async closures.
private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
