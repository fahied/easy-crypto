
//
//  MarginTradeImportServiceTests.swift
//  EasyCryptoTests
//
//  Tests for ADV-CORE-SERVICES-006: MarginTradeImportService
//  Tests for ADV-CORE-SERVICES-010: Static asset lists, no retry, per-symbol error handling.
//
//  Mirrors TradeImportServiceTests patterns but verifies margin-specific behavior:
//  TradingMode parameter, static asset lists, per-symbol sync cursors, cross/isolated
//  branching, and per-symbol error handling without retry logic.
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

private func makeMarginClient(
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
                maintained: nil, userAssets: []
            )
        },
        fetchMarginMyTrades: { symbol, _, isIsolated in tradesForSymbol(symbol, isIsolated) },
        fetchMarginOpenOrders: { _, _ in [] },
        fetchMarginAllAssets: { [] },
        fetchIsolatedMarginTransfers: { _ in [] }
    )
}

// MARK: - Static Asset List Tests

@Suite("Given a margin trade import service with static asset lists")
struct MarginStaticAssetListTests {

    @Test("When crossMargin with no existingSync, then all static list symbols are synced")
    func crossMarginSyncsAllStaticAssets() async throws {
        let client = makeMarginClient { symbol, _ in
            [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        for asset in MarginTradeImportService.knownCrossMarginAssets {
            #expect(symbols.contains("\(asset)USDT"),
                "\(asset)USDT should be synced from cross-margin static list")
        }
    }

    @Test("When isolatedMargin with no existingSync, then all static list symbols are synced")
    func isolatedMarginSyncsAllStaticAssets() async throws {
        let client = makeMarginClient { symbol, _ in
            [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, [:])

        let symbols = Set(result.mappedTrades.map(\.symbol))
        for asset in MarginTradeImportService.knownIsolatedMarginAssets {
            #expect(symbols.contains("\(asset)USDT"),
                "\(asset)USDT should be synced from isolated-margin static list")
        }
    }

    @Test("existingSync keys outside the static list are ignored for cross-margin")
    func crossMarginExistingSyncDoesNotExpandList() async throws {
        var fetchedSymbols: [String] = []
        let client = makeMarginClient { symbol, _ in
            fetchedSymbols.append(symbol)
            return [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        // DOGEUSDT is NOT in the static list — should never be fetched
        let result = try await service.sync(.crossMargin, ["DOGEUSDT": 500])

        #expect(!fetchedSymbols.contains("DOGEUSDT"),
            "existingSync keys outside static list must be ignored")
        #expect(fetchedSymbols.count == 6, "only the 6 static assets are fetched")
    }

    @Test("existingSync keys outside the static list are ignored for isolated-margin")
    func isolatedMarginExistingSyncDoesNotExpandList() async throws {
        var fetchedSymbols: [String] = []
        let client = makeMarginClient { symbol, _ in
            fetchedSymbols.append(symbol)
            return [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        // ADAUSDT is NOT in the static list — should never be fetched
        let result = try await service.sync(.isolatedMargin, ["ADAUSDT": 500])

        #expect(!fetchedSymbols.contains("ADAUSDT"),
            "existingSync keys outside static list must be ignored")
        #expect(fetchedSymbols.count == 3, "only the 3 static assets are fetched")
    }

    @Test("Cross-margin static list contains the correct six assets")
    func crossMarginStaticListContents() {
        let assets = MarginTradeImportService.knownCrossMarginAssets
        #expect(assets.contains("SOL"))
        #expect(assets.contains("DEXE"))
        #expect(assets.contains("MMT"))
        #expect(assets.contains("BANK"))
        #expect(assets.contains("LTC"))
        #expect(assets.contains("XRP"))
        #expect(assets.count == 6)
    }

    @Test("Isolated-margin static list contains the correct three assets")
    func isolatedMarginStaticListContents() {
        let assets = MarginTradeImportService.knownIsolatedMarginAssets
        #expect(assets.contains("DEXE"))
        #expect(assets.contains("MMT"))
        #expect(assets.contains("XRP"))
        #expect(assets.count == 3)
    }

    @Test("existingSync cannot inject symbols beyond the static list")
    func existingSyncDoesNotExpandAssetList() async throws {
        var fetchedSymbols: [String] = []
        let client = makeMarginClient { symbol, _ in
            fetchedSymbols.append(symbol)
            return [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        // UNKNOWN is NOT in the static list — should never be fetched
        let result = try await service.sync(.crossMargin, ["UNKNOWNUSDT": 500])

        #expect(!fetchedSymbols.contains("UNKNOWNUSDT"),
            "existingSync keys outside the static list must be ignored")
        #expect(fetchedSymbols.count == 6,
            "only the 6 static cross-margin assets should be synced")
    }
}

// MARK: - Incremental Sync Tests

@Suite("Given a margin trade import service with existing sync metadata")
struct MarginIncrementalSyncTests {

    @Test("When crossMargin has existingSync, fromId starts at lastTradeId + 1")
    func crossMarginRespectsFromId() async throws {
        let client = makeMarginClient { symbol, _ in
            if symbol == "SOLUSDT" {
                return [makeMarginTrade(id: 51, symbol: symbol)]
            }
            return []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, ["SOLUSDT": 50])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 51)
    }

    @Test("When isolatedMargin has existingSync, fromId starts at lastTradeId + 1")
    func isolatedMarginRespectsFromId() async throws {
        let client = makeMarginClient { symbol, _ in
            if symbol == "DEXEUSDT" {
                return [makeMarginTrade(id: 101, symbol: symbol)]
            }
            return []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["DEXEUSDT": 100])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 101)
    }

    @Test("When crossMargin existingSync is empty, fromId is nil (full fetch)")
    func crossMarginNoExistingSyncDoesFullFetch() async throws {
        let client = makeMarginClient { symbol, _ in
            if symbol == "XRPUSDT" {
                return [makeMarginTrade(id: 1, symbol: symbol)]
            }
            return []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 1)
    }

    @Test("When isolatedMargin existingSync is empty, fromId is nil (full fetch)")
    func isolatedMarginNoExistingSyncDoesFullFetch() async throws {
        let client = makeMarginClient { symbol, _ in
            if symbol == "MMTUSDT" {
                return [makeMarginTrade(id: 1, symbol: symbol)]
            }
            return []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, [:])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades.first?.binanceTradeId == 1)
    }
}

// MARK: - Mode Tests

@Suite("Given a margin trade import service routing by TradingMode")
struct MarginModeTests {

    @Test("When TradingMode.crossMargin, then fetchMarginMyTrades called with isIsolated=false")
    func crossMarginUsesCorrectEndpoint() async throws {
        let calls = Locked<[(symbol: String, isIsolated: Bool)]>([])

        let client = makeMarginClient { symbol, isIsolated in
            calls.value.append((symbol, isIsolated))
            return [makeMarginTrade(id: 1, symbol: symbol, isIsolated: false)]
        }

        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.crossMargin, [:])

        let btcCall = try #require(calls.value.first { $0.symbol == "BTCUSDT" })
        #expect(btcCall.isIsolated == false)
    }

    @Test("When TradingMode.isolatedMargin, then fetchMarginMyTrades called with isIsolated=true")
    func isolatedMarginUsesCorrectEndpoint() async throws {
        let calls = Locked<[(symbol: String, isIsolated: Bool)]>([])

        let client = makeMarginClient { symbol, isIsolated in
            calls.value.append((symbol, isIsolated))
            return [makeMarginTrade(id: 1, symbol: symbol, isIsolated: true)]
        }

        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.isolatedMargin, ["BTCUSDT": 0])

        let btcCall = try #require(calls.value.first { $0.symbol == "BTCUSDT" })
        #expect(btcCall.isIsolated == true)
    }
}

// MARK: - Sync Metadata Tests

@Suite("Given a margin trade import service generating sync updates")
struct MarginSyncMetadataTests {

    @Test("When crossMargin syncs, then sync update uses the symbol as key")
    func crossMarginSyncUsesSymbolKey() async throws {
        let client = makeMarginClient { symbol, _ in
            [makeMarginTrade(id: 50, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, ["SOLUSDT": 10])

        let update = try #require(result.syncUpdates.first { $0.symbol == "SOLUSDT" })
        #expect(update.lastTradeId == 50)
    }

    @Test("When isolatedMargin syncs, then sync update uses the symbol as key")
    func isolatedMarginSyncUsesSymbolKey() async throws {
        let client = makeMarginClient { symbol, _ in
            [makeMarginTrade(id: 75, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["DEXEUSDT": 10])

        let update = try #require(result.syncUpdates.first { $0.symbol == "DEXEUSDT" })
        #expect(update.lastTradeId == 75)
    }

    @Test("When multiple cross-margin symbols have trades, then each gets a sync update")
    func crossMarginMultipleSyncUpdates() async throws {
        let client = makeMarginClient { symbol, _ in
            if symbol == "SOLUSDT" {
                return [makeMarginTrade(id: 10, symbol: symbol)]
            } else if symbol == "XRPUSDT" {
                return [makeMarginTrade(id: 20, symbol: symbol)]
            }
            return []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        #expect(result.syncUpdates.count == 2)
        let solUpdate = result.syncUpdates.first { $0.symbol == "SOLUSDT" }
        let xrpUpdate = result.syncUpdates.first { $0.symbol == "XRPUSDT" }
        #expect(solUpdate?.lastTradeId == 10)
        #expect(xrpUpdate?.lastTradeId == 20)
    }

    @Test("When no trades returned, then no sync updates are produced")
    func noTradesNoSyncUpdates() async throws {
        let client = makeMarginClient { _, _ in [] }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        #expect(result.syncUpdates.isEmpty)
    }
}

// MARK: - Trade Mapping Tests

@Suite("Given a margin trade import service mapping API responses")
struct MarginTradeMappingTests {

    @Test("When API returns a margin trade, then all fields are mapped correctly")
    func mapsAllFields() async throws {
        let client = makeMarginClient { symbol, _ in
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
        let client = makeMarginClient { symbol, _ in
            symbol == "ETHUSDT"
                ? [makeMarginTrade(id: 1, symbol: "ETHUSDT", isBuyer: false)]
                : []
        }
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.isBuyer == false)
        #expect(trade.asset == "ETH")
    }

    @Test("When BinanceMarginTrade has isIsolated=true, then still mapped correctly")
    func mapsIsolatedMarginTrade() async throws {
        let client = makeMarginClient { symbol, _ in
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
        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, ["ETHUSDT": 0])

        let trade = try #require(result.mappedTrades.first)
        #expect(trade.binanceTradeId == 42)
        #expect(trade.symbol == "ETHUSDT")
        #expect(trade.asset == "ETH")
    }
}

// MARK: - Error Handling Tests

@Suite("Given a margin trade import service with API errors")
struct MarginErrorTests {

    @Test("When fetchMarginMyTrades fails for one cross-margin symbol, then other symbols still sync")
    func crossMarginPartialFailureContinues() async throws {
        let client = BinanceAPIClient(
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
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { symbol, _, _ in
                if symbol == "SOLUSDT" {
                    throw BinanceError.apiError(code: -1121, message: "Invalid symbol")
                }
                if symbol == "XRPUSDT" {
                    return [makeMarginTrade(id: 1, symbol: symbol)]
                }
                return []
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        // XRP should still succeed despite SOL failure
        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades[0].symbol == "XRPUSDT")
    }

    @Test("When fetchMarginMyTrades fails for one isolated-margin symbol, then other symbols still sync")
    func isolatedMarginPartialFailureContinues() async throws {
        let client = BinanceAPIClient(
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
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { symbol, _, _ in
                if symbol == "DEXEUSDT" {
                    throw BinanceError.apiError(code: -1121, message: "Invalid symbol")
                }
                if symbol == "MMTUSDT" {
                    return [makeMarginTrade(id: 1, symbol: symbol)]
                }
                return []
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.isolatedMargin, [:])

        #expect(result.mappedTrades.count == 1)
        #expect(result.mappedTrades[0].symbol == "MMTUSDT")
    }

    @Test("When all cross-margin symbols fail, then returns empty result with no sync updates")
    func allCrossMarginSymbolsFailReturnsEmpty() async throws {
        let client = BinanceAPIClient(
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
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { _, _, _ in
                throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet))
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        #expect(result.mappedTrades.isEmpty)
        #expect(result.syncUpdates.isEmpty)
    }
}

// MARK: - No-Retry Behavior Tests

@Suite("Given a margin trade import service with no retry logic")
struct MarginNoRetryTests {

    @Test("When crossMargin fetch succeeds, each static asset is fetched exactly once")
    func crossMarginNoDuplicateFetches() async throws {
        let callCount = Locked<[String: Int]>([:])
        let client = makeMarginClient { symbol, _ in
            var counts = callCount.value
            counts[symbol, default: 0] += 1
            callCount.value = counts
            return [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.crossMargin, [:])

        let counts = callCount.value
        for asset in MarginTradeImportService.knownCrossMarginAssets {
            let symbol = "\(asset)USDT"
            let fetchCount = counts[symbol] ?? 0
            #expect(fetchCount == 1,
                "\(symbol) should be fetched exactly once, got \(fetchCount)")
        }
    }

    @Test("When isolatedMargin fetch succeeds, each static asset is fetched exactly once")
    func isolatedMarginNoDuplicateFetches() async throws {
        let callCount = Locked<[String: Int]>([:])
        let client = makeMarginClient { symbol, _ in
            var counts = callCount.value
            counts[symbol, default: 0] += 1
            callCount.value = counts
            return [makeMarginTrade(id: 1, symbol: symbol)]
        }
        let service = MarginTradeImportService.live(apiClient: client)
        _ = try await service.sync(.isolatedMargin, [:])

        let counts = callCount.value
        for asset in MarginTradeImportService.knownIsolatedMarginAssets {
            let symbol = "\(asset)USDT"
            let fetchCount = counts[symbol] ?? 0
            #expect(fetchCount == 1,
                "\(symbol) should be fetched exactly once, got \(fetchCount)")
        }
    }

    @Test("When crossMargin fetch fails, each static asset is fetched exactly once (no retry)")
    func crossMarginFailedSymbolNotRetried() async throws {
        let client = BinanceAPIClient(
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
                    maintained: nil, userAssets: []
                )
            },
            fetchMarginMyTrades: { symbol, _, _ in
                // Always fail — if retry existed, this would be called >1 time per symbol
                throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet))
            },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginTradeImportService.live(apiClient: client)
        let result = try await service.sync(.crossMargin, [:])

        // All symbols should have empty results, no crash, no retries
        #expect(result.mappedTrades.isEmpty)
        #expect(result.syncUpdates.isEmpty)
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

/// A simple thread-safe wrapper for tracking values across async closures.
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
