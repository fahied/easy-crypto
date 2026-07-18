//
//  TradeImportServiceTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing

@testable import EasyCrypto

// MARK: - Helpers

private func makeBinanceTrade(
    id: Int64,
    symbol: String = "BTCUSDT",
    price: String = "50000.00",
    qty: String = "1.0",
    quoteQty: String = "50000.00",
    commission: String = "0.001",
    commissionAsset: String = "BTC",
    time: Int64 = 1_700_000_000_000,
    isBuyer: Bool = true,
    orderId: Int64 = 100
) -> BinanceTrade {
    BinanceTrade(
        id: id, symbol: symbol, price: price, qty: qty,
        quoteQty: quoteQty, commission: commission,
        commissionAsset: commissionAsset, time: time,
        isBuyer: isBuyer, orderId: orderId
    )
}

private func makeBalance(_ asset: String) -> BinanceBalance {
    BinanceBalance(asset: asset, free: "1.0", locked: "0")
}

private func makeClient(
    balances: [BinanceBalance] = [],
    tradesForSymbol: @escaping @Sendable (String, Int64?) -> [BinanceTrade] = { _, _ in [] }
) -> BinanceAPIClient {
    BinanceAPIClient(
        fetchAccount: { balances },
        fetchMyTrades: { symbol, fromId in tradesForSymbol(symbol, fromId) },
        fetchTickerPrices: { _ in [] },
        fetchKlines: { _, _, _ in [] }
    )
}

// MARK: - Asset Discovery Tests

@Suite("Given a trade import service discovering assets")
struct AssetDiscoveryTests {

    @Test("When account has BTC and ETH, then fetches trades for both symbols")
    func discoversMultipleAssets() async throws {
        let client = BinanceAPIClient(
            fetchAccount: { [makeBalance("BTC"), makeBalance("ETH")] },
            fetchMyTrades: { symbol, _ in
                // Return one trade per symbol so we can verify which symbols were fetched
                [makeBinanceTrade(id: 1, symbol: symbol)]
            },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        #expect(symbols.contains("BTCUSDT"))
        #expect(symbols.contains("ETHUSDT"))
    }

    @Test("When account has USDT balance, then USDT is excluded from sync")
    func excludesUSDT() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC"), makeBalance("USDT")],
            tradesForSymbol: { symbol, _ in
                [makeBinanceTrade(id: 1, symbol: symbol)]
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        #expect(symbols.contains("BTCUSDT"))
        #expect(!symbols.contains("USDTUSDT"))
    }

    @Test("When account is empty, then bootstrap symbols are still requested")
    func bootstrapSymbolsAreFetchedOnFreshSync() async throws {
        let client = makeClient(
            balances: [],
            tradesForSymbol: { symbol, _ in
                [makeBinanceTrade(id: 1, symbol: symbol)]
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        #expect(symbols.contains("BTCUSDT"))
        #expect(symbols.contains("SOLUSDT"))
        #expect(symbols.contains("IOTXUSDT"))
        #expect(symbols.contains("BNBUSDT"))
    }

    @Test("When account has ETH, then bootstrap symbols are added to the sync set")
    func addsBootstrapSymbolsToBalanceAssets() async throws {
        let client = makeClient(
            balances: [makeBalance("ETH")],
            tradesForSymbol: { symbol, _ in
                [makeBinanceTrade(id: 1, symbol: symbol)]
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        #expect(symbols.contains("ETHUSDT"))
        #expect(symbols.contains("BTCUSDT"))
        #expect(symbols.contains("SOLUSDT"))
        #expect(symbols.contains("IOTXUSDT"))
        #expect(symbols.contains("BNBUSDT"))
    }

}

// MARK: - Trade Mapping Tests

@Suite("Given a trade import service mapping API responses")
struct TradeMappingTests {

    @Test("When API returns a trade, then all fields are mapped correctly")
    func mapsAllFields() async throws {
        let apiTrade = BinanceTrade(
            id: 12345, symbol: "BTCUSDT", price: "50000.50",
            qty: "0.25", quoteQty: "12500.125",
            commission: "0.001", commissionAsset: "BTC",
            time: 1_700_000_000_000, isBuyer: true, orderId: 9876
        )
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? [apiTrade] : [] }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

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
            balances: [makeBalance("ETH")],
            tradesForSymbol: { symbol, _ in
                symbol == "ETHUSDT"
                    ? [makeBinanceTrade(id: 1, symbol: "ETHUSDT", isBuyer: false)]
                    : []
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.isBuyer == false)
        #expect(trade.asset == "ETH")
    }
}

// MARK: - Pagination Tests

@Suite("Given a trade import service with pagination")
struct PaginationTests {

    @Test("When API returns fewer than 1000 trades, then only one fetch per symbol")
    func singlePage() async throws {
        let trades = (0..<5).map { makeBinanceTrade(id: Int64($0)) }
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, _ in symbol == "BTCUSDT" ? trades : [] }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        #expect(result.mappedTrades.count == 5)
    }

    @Test("When API returns exactly 1000, then fetches next page with fromId")
    func paginatesOnFullPage() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, fromId in
                guard symbol == "BTCUSDT" else { return [] }
                if fromId == nil {
                    // First page: 1000 trades with IDs 0...999
                    return (0..<1000).map {
                        makeBinanceTrade(id: Int64($0), time: 1_700_000_000_000 + Int64($0))
                    }
                } else {
                    // Second page: 200 trades with IDs 1000...1199
                    return (1000..<1200).map {
                        makeBinanceTrade(id: Int64($0), time: 1_700_000_000_000 + Int64($0))
                    }
                }
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        #expect(result.mappedTrades.count == 1200)
    }

    @Test("When second page returns exactly 1000, then fetches a third page")
    func multiplePages() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, fromId in
                guard symbol == "BTCUSDT" else { return [] }
                if fromId == nil {
                    return (0..<1000).map { makeBinanceTrade(id: Int64($0)) }
                } else if fromId == 1000 {
                    return (1000..<2000).map { makeBinanceTrade(id: Int64($0)) }
                } else {
                    return (2000..<2500).map { makeBinanceTrade(id: Int64($0)) }
                }
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        #expect(result.mappedTrades.count == 2500)
    }

    @Test("When paginating, then fromId is last trade ID + 1")
    func paginationFromIdIsCorrect() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { _, fromId in
                if fromId == nil {
                    // IDs 10, 20, 30...1000 (100 items but pretend full page)
                    return (0..<1000).map { makeBinanceTrade(id: Int64($0) * 10) }
                } else {
                    // fromId should be 9991 (last was 9990, + 1)
                    #expect(fromId == 9991)
                    return []
                }
            }
        )
        let service = TradeImportService.live(apiClient: client)
        _ = try await service.sync([:])
    }
}

// MARK: - Incremental Sync Tests

@Suite("Given a trade import service with existing sync metadata")
struct IncrementalSyncTests {

    @Test("When a symbol exists only in sync metadata, then it still fetches new trades")
    func syncsPreviouslyTrackedSymbolWithZeroBalance() async throws {
        let client = makeClient(
            balances: [makeBalance("ETH")],
            tradesForSymbol: { symbol, fromId in
                if symbol == "BTCUSDT" {
                    #expect(fromId == 501)
                    return [makeBinanceTrade(id: 501, symbol: symbol, isBuyer: false)]
                }

                // ETH balance and bootstrap symbols return no new trades
                return []
            }
        )
        let service = TradeImportService.live(apiClient: client)

        let result = try await service.sync(["BTCUSDT": 500])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.symbol == "BTCUSDT")
    }

    @Test("When existingSync has lastTradeId, then fromId starts at lastTradeId + 1")
    func usesExistingSyncMetadata() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, fromId in
                guard symbol == "BTCUSDT" else { return [] }
                #expect(fromId == 501)
                return [makeBinanceTrade(id: 501), makeBinanceTrade(id: 502)]
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync(["BTCUSDT": 500])

        #expect(result.mappedTrades.count == 2)
    }

    @Test("When existingSync is empty for symbol, then fromId is nil (full fetch)")
    func noSyncMetadataFetchesAll() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { _, fromId in
                #expect(fromId == nil)
                return [makeBinanceTrade(id: 1)]
            }
        )
        let service = TradeImportService.live(apiClient: client)
        _ = try await service.sync([:])
    }

    @Test("When multiple symbols have different sync states, then each uses its own fromId")
    func perSymbolSyncState() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC"), makeBalance("ETH")],
            tradesForSymbol: { symbol, fromId in
                if symbol == "BTCUSDT" {
                    #expect(fromId == 101)
                    return [makeBinanceTrade(id: (fromId ?? 0) + 1, symbol: symbol)]
                } else if symbol == "ETHUSDT" {
                    #expect(fromId == 201)
                    return [makeBinanceTrade(id: (fromId ?? 0) + 1, symbol: symbol)]
                }
                return []
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync(["BTCUSDT": 100, "ETHUSDT": 200])

        #expect(result.mappedTrades.count == 2)
    }
}

// MARK: - Sync Metadata Update Tests

@Suite("Given a trade import service generating sync updates")
struct SyncUpdateTests {

    @Test("When trades are fetched, then sync update has the last trade ID")
    func syncUpdateHasLastTradeId() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { symbol, _ in
                symbol == "BTCUSDT"
                    ? [makeBinanceTrade(id: 50), makeBinanceTrade(id: 100), makeBinanceTrade(id: 75)]
                    : []
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        let update = try #require(result.syncUpdates.first)
        #expect(update.symbol == "BTCUSDT")
        // Last trade in the array is id=75, that's the last received
        #expect(update.lastTradeId == 75)
    }

    @Test("When no trades returned for a symbol, then no sync update for that symbol")
    func noTradesNoSyncUpdate() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC")],
            tradesForSymbol: { _, _ in [] }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        #expect(result.syncUpdates.isEmpty)
    }

    @Test("When multiple symbols have trades, then each gets a sync update")
    func multipleSyncUpdates() async throws {
        let client = makeClient(
            balances: [makeBalance("BTC"), makeBalance("ETH")],
            tradesForSymbol: { symbol, _ in
                if symbol == "BTCUSDT" {
                    return [makeBinanceTrade(id: 10, symbol: symbol)]
                } else if symbol == "ETHUSDT" {
                    return [makeBinanceTrade(id: 20, symbol: symbol)]
                }
                return []
            }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        #expect(result.syncUpdates.count == 2)
        let btcUpdate = result.syncUpdates.first { $0.symbol == "BTCUSDT" }
        let ethUpdate = result.syncUpdates.first { $0.symbol == "ETHUSDT" }
        #expect(btcUpdate?.lastTradeId == 10)
        #expect(ethUpdate?.lastTradeId == 20)
    }
}

// MARK: - Error Handling Tests

@Suite("Given a trade import service with API errors")
struct ImportErrorTests {

    @Test("When fetchAccount throws, then error propagates")
    func accountErrorPropagates() async {
        let client = BinanceAPIClient(
            fetchAccount: { throw BinanceError.invalidCredentials },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )
        let service = TradeImportService.live(apiClient: client)

        do {
            _ = try await service.sync([:])
            Issue.record("Expected error to propagate")
        } catch {
            guard case BinanceError.invalidCredentials = error else {
                Issue.record("Expected invalidCredentials, got \(error)")
                return
            }
        }
    }

    @Test("When fetchMyTrades throws for one symbol, then other symbols still sync")
    func partialFailureContinues() async throws {
        let client = BinanceAPIClient(
            fetchAccount: { [makeBalance("BTC"), makeBalance("ETH")] },
            fetchMyTrades: { symbol, _ in
                if symbol == "BTCUSDT" {
                    throw BinanceError.apiError(code: -1121, message: "Invalid symbol")
                }
                if symbol == "ETHUSDT" {
                    return [makeBinanceTrade(id: 1, symbol: symbol)]
                }
                return []
            },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )
        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        // ETH should still succeed
        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades[0].symbol == "ETHUSDT")
    }
}

// MARK: - Rate-Limit Retry Tests

@Suite("Given a trade import service handling rate limits")
struct RateLimitRetryTests {

    @Test("When a symbol is rate limited then succeeds, then retries and fetches trades")
    func retriesOnRateLimit() async throws {
        let callCount = Locked(0)

        let client = BinanceAPIClient(
            fetchAccount: { [makeBalance("BTC")] },
            fetchMyTrades: { symbol, _ in
                callCount.value += 1
                if callCount.value == 1 {
                    throw BinanceError.rateLimited(retryAfterSeconds: nil)
                }
                return [makeBinanceTrade(id: 1, symbol: symbol)]
            },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )

        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        // Should have retried at least once
        #expect(callCount.value >= 2)
        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades[0].symbol == "BTCUSDT")
    }

    @Test("When a symbol is rate limited on all retries, then it is skipped")
    func skipsAfterExhaustingRateLimitRetries() async throws {
        let client = BinanceAPIClient(
            fetchAccount: { [makeBalance("BTC")] },
            fetchMyTrades: { _, _ in
                throw BinanceError.rateLimited(retryAfterSeconds: nil)
            },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )

        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        // No trades after exhausting retries
        #expect(result.mappedTrades.isEmpty)
        #expect(result.syncUpdates.isEmpty)
    }

    @Test("When rate limited then succeeds, other symbols still sync")
    func rateLimitRetryDoesNotBlockOtherSymbols() async throws {
        let btcCallCount = Locked(0)

        let client = BinanceAPIClient(
            fetchAccount: { [makeBalance("BTC"), makeBalance("ETH")] },
            fetchMyTrades: { symbol, _ in
                if symbol == "BTCUSDT" {
                    btcCallCount.value += 1
                    if btcCallCount.value == 1 {
                        throw BinanceError.rateLimited(retryAfterSeconds: nil)
                    }
                    return [makeBinanceTrade(id: 1, symbol: symbol)]
                }
                return [makeBinanceTrade(id: 2, symbol: symbol)]
            },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] }
        )

        let service = TradeImportService.live(apiClient: client)
        let result = try await service.sync([:])

        // Both symbols should have trades
        #expect(result.mappedTrades.count == 2)
        let symbols = Set(result.mappedTrades.map(\.symbol))
        #expect(symbols.contains("BTCUSDT"))
        #expect(symbols.contains("ETHUSDT"))
    }
}

// MARK: - Preview/Noop Client Tests

@Suite("Given a preview TradeImportService")
struct PreviewImportTests {

    @Test("When using preview service, then returns sample data")
    func previewReturnsSampleData() async throws {
        let result = try await TradeImportService.preview.sync([:])
        #expect(!result.mappedTrades.isEmpty)
    }

    @Test("When using noop service, then returns empty result")
    func noopReturnsEmpty() async throws {
        let result = try await TradeImportService.noop.sync([:])
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
