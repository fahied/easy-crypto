//
//  MarginBalanceServiceTests.swift
//  EasyCryptoTests
//
//  ADV-CORE-SERVICES-007: Tests for MarginBalanceService.
//
//  Target: 7 tests covering DTO mapping, isolated-margin construction, preview/noop variants,
//  and live service wiring against stubbed BinanceAPIClient closures.

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given a MarginBalanceService")
struct MarginBalanceServiceTests {

    // MARK: - CrossMarginAccountData

    @Test("When decoding from a margin account with userAssets, then perAssetInterest is derived")
    func crossMarginDerivesPerAssetInterest() throws {
        let account = BinanceMarginAccount(
            marginLevel: "3.5",
            totalAssetOfBtc: "0.15",
            totalLiabilityOfBtc: "0.04",
            totalNetAssetOfBtc: "0.11",
            totalAsset: "10000",
            totalLiability: "2800",
            totalNetAsset: "7200",
            maxBorrowable: "5000",
            maintained: nil,
            userAssets: [
                .init(asset: "BTC", borrowed: "0.5", free: "0.2", locked: "0.1",
                      interest: "0.001", netAsset: "-0.2", netAssetOfBtc: "0.001",
                      maxBorrowable: "1.0"),
                .init(asset: "SOL", borrowed: "100", free: "50", locked: "10",
                      interest: "0.5", netAsset: "59.5", netAssetOfBtc: "0.01",
                      maxBorrowable: "200"),
                .init(asset: "USDT", borrowed: "0", free: "500", locked: "0",
                      interest: "0", netAsset: "500", netAssetOfBtc: "0",
                      maxBorrowable: "1000"),
            ]
        )

        let data = try CrossMarginAccountData(from: account)

        #expect(data.marginLevel == 3.5)
        #expect(data.totalAsset == 10000)
        #expect(data.totalNetAsset == 7200)
        #expect(data.perAssetInterest["BTC"] == 0.001)
        #expect(data.perAssetInterest["SOL"] == 0.5)
        #expect(data.perAssetInterest["USDT"] == nil)
        #expect(data.perAssetInterest.count == 2)
        #expect(data.netAsset == data.totalNetAsset)
    }

    @Test("When decoding from a margin account with no userAssets, then perAssetInterest is empty")
    func crossMarginEmptyUserAssets() throws {
        let account = BinanceMarginAccount(
            marginLevel: "0",
            totalAssetOfBtc: "0",
            totalLiabilityOfBtc: "0",
            totalNetAssetOfBtc: "0",
            totalAsset: "0",
            totalLiability: "0",
            totalNetAsset: "0",
            maxBorrowable: "0",
            maintained: nil,
            userAssets: []
        )

        let data = try CrossMarginAccountData(from: account)

        #expect(data.totalNetAsset == 0)
        #expect(data.perAssetInterest.isEmpty)
        #expect(data.netAsset == 0)
    }

    // MARK: - IsolatedMarginBalance

    @Test("When building from asset detail with risk data, then all fields are mapped correctly")
    func isolatedMarginBalanceMapsAllFields() {
        let assetDetail = BinanceIsolatedMarginAccount.AssetDetail(
            asset: "BTC",
            borrowed: "0.5",
            free: "0.2",
            locked: "0.1",
            interest: "0.01",
            netAsset: "0.59"
        )

        let balance = IsolatedMarginBalance.from(
            assetDetail: assetDetail,
            symbol: "BTCUSDT",
            role: .base,
            liquidationPrice: "42000",
            marginLevel: "2.1"
        )

        #expect(balance.symbol == "BTCUSDT")
        #expect(balance.asset == "BTC")
        #expect(balance.role == .base)
        #expect(abs(balance.borrowed - 0.5) < 1e-9)
        #expect(abs(balance.free - 0.2) < 1e-9)
        #expect(abs(balance.interest - 0.01) < 1e-9)
        #expect(abs(balance.netAsset - 0.59) < 1e-9)
        #expect(balance.liquidationPrice == "42000")
        #expect(balance.marginLevel == "2.1")
    }

    @Test("When risk strings are omitted, then liquidationPrice and marginLevel are empty")
    func isolatedMarginBalanceDefaultsRiskFields() {
        let assetDetail = BinanceIsolatedMarginAccount.AssetDetail(
            asset: "USDT",
            borrowed: "0",
            free: "5000",
            locked: "0",
            interest: "0",
            netAsset: "5000"
        )

        let balance = IsolatedMarginBalance.from(
            assetDetail: assetDetail,
            symbol: "BTCUSDT",
            role: .quote
        )

        #expect(balance.asset == "USDT")
        #expect(balance.role == .quote)
        #expect(balance.liquidationPrice.isEmpty)
        #expect(balance.marginLevel.isEmpty)
        #expect(abs(balance.netAsset - 5000) < 1e-9)
    }

    // MARK: - Preview & Noop

    @Test("When using preview, then fetchCrossMarginAccount returns populated data")
    func previewReturnsCrossMarginData() async throws {
        let data = try await MarginBalanceService.preview.fetchCrossMarginAccount()

        #expect(data != nil)
        #expect(data!.perAssetInterest["BTC"] == 0.001)
        #expect(data!.netAsset > 0)
    }

    @Test("When using noop, then fetchCrossMarginAccount returns nil and isolated returns nil")
    func noopReturnsDefaults() async throws {
        #expect(try await MarginBalanceService.noop.fetchCrossMarginAccount() == nil)
        #expect(try await MarginBalanceService.noop.fetchIsolatedMarginBalances("BTCUSDT") == nil)
    }

    // MARK: - Live Service

    private func makeCrossMarginClient(
        userAssets: [BinanceMarginAccount.AssetEntry] = []
    ) -> BinanceAPIClient {
        BinanceAPIClient(
            fetchAccount: { [BinanceBalance(asset: "BTC", free: "0.1", locked: "0")] },
            fetchMyTrades: { _, _ in [] },
            fetchTickerPrices: { _ in [] },
            fetchKlines: { _, _, _ in [] },
            fetchMarginAccount: {
                BinanceMarginAccount(
                    marginLevel: userAssets.isEmpty ? "0" : "5.0",
                    totalAssetOfBtc: userAssets.isEmpty ? "0" : "0.2",
                    totalLiabilityOfBtc: userAssets.isEmpty ? "0" : "0.04",
                    totalNetAssetOfBtc: userAssets.isEmpty ? "0" : "0.16",
                    totalAsset: userAssets.isEmpty ? "0" : "20000",
                    totalLiability: userAssets.isEmpty ? "0" : "4000",
                    totalNetAsset: userAssets.isEmpty ? "0" : "16000",
                    maxBorrowable: userAssets.isEmpty ? "0" : "8000",
                    maintained: nil,
                    userAssets: userAssets
                )
            },
            fetchIsolatedMarginAccount: { _ in .empty },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [BinanceMarginAsset]() },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
    }

    @Test("When fetchCrossMarginAccount succeeds, then it maps all DTO fields and derives perAssetInterest")
    func liveCrossMarginMapsCorrectly() async throws {
        let userAssets: [BinanceMarginAccount.AssetEntry] = [
            .init(asset: "BTC", borrowed: "1.0", free: "0.5", locked: "0.1",
                  interest: "0.01", netAsset: "0.59", netAssetOfBtc: "0.01",
                  maxBorrowable: "2.0"),
            .init(asset: "ETH", borrowed: "0", free: "0", locked: "0",
                  interest: "0", netAsset: "0", netAssetOfBtc: "0",
                  maxBorrowable: "0"),
        ]
        let apiClient = makeCrossMarginClient(userAssets: userAssets)

        let service = MarginBalanceService.live(apiClient: apiClient)
        let cross = try await service.fetchCrossMarginAccount()

        #expect(cross != nil)
        #expect(cross!.totalNetAsset == 16000)
        #expect(cross!.perAssetInterest["BTC"] == 0.01)
        #expect(cross!.perAssetInterest["ETH"] == nil)
        #expect(cross!.maxBorrowable == 8000)
    }

    @Test("When cross-margin account has no userAssets, then fetchCrossMarginAccount returns nil")
    func liveCrossMarginEmptyAccount() async throws {
        let apiClient = makeCrossMarginClient(userAssets: [])

        let service = MarginBalanceService.live(apiClient: apiClient)
        let result = try await service.fetchCrossMarginAccount()
        #expect(result == nil)
    }

    @Test("When fetchIsolatedMarginAccount returns a pair, then per-asset balances include risk data")
    func liveIsolatedBuildsBalancesFromAccount() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.1", locked: "0")
            ] },
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
                BinanceIsolatedMarginAccount(
                    assets: [
                        .init(
                            symbol: "BTCUSDT",
                            marginLevel: "2.5",
                            marginRatio: "1.5",
                            indexPrice: "50000",
                            liquidatePrice: "30000",
                            liquidateRate: "0.1",
                            tradeEnabled: true,
                            enabled: true,
                            baseAsset: .init(
                                asset: "BTC", borrowed: "0.5", free: "0.2",
                                locked: "0.1", interest: "0.01", netAsset: "0.59"
                            ),
                            quoteAsset: .init(
                                asset: "USDT", borrowed: "0", free: "5000",
                                locked: "0", interest: "0", netAsset: "5000"
                            )
                        )
                    ],
                    totalAssetOfBtc: "0.16",
                    totalLiabilityOfBtc: "0.04",
                    totalNetAssetOfBtc: "0.12"
                )
            },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [BinanceMarginAsset]() },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginBalanceService.live(apiClient: apiClient)
        let result = try await service.fetchIsolatedMarginBalances("BTCUSDT")

        #expect(result != nil)
        #expect(result!.count == 2)

        let btc = result!.first { $0.asset == "BTC" }
        #expect(btc != nil)
        #expect(btc!.role == .base)
        #expect(abs(btc!.borrowed - 0.5) < 1e-9)
        #expect(btc!.liquidationPrice == "30000")
        #expect(btc!.marginLevel == "2.5")

        let usdt = result!.first { $0.asset == "USDT" }
        #expect(usdt != nil)
        #expect(usdt!.role == .quote)
        #expect(abs(usdt!.netAsset - 5000) < 1e-9)
        #expect(usdt!.liquidationPrice == "30000")
        #expect(usdt!.marginLevel == "2.5")
    }

    @Test("When fetchIsolatedMarginAccount returns empty, then fetchIsolatedMarginBalances returns empty")
    func liveIsolatedEmptyReturnsEmpty() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.1", locked: "0")
            ] },
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
            fetchIsolatedMarginAccount: { _ in .empty },
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [BinanceMarginAsset]() },
            fetchIsolatedMarginTransfers: { _ in [] }
        )

        let service = MarginBalanceService.live(apiClient: apiClient)
        let result = try await service.fetchIsolatedMarginBalances("BTCUSDT")
        #expect((result ?? []).isEmpty)
    }
}
