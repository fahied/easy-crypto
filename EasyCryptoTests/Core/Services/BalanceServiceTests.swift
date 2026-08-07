//
//  BalanceServiceTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given a live BalanceService")
struct BalanceServiceTests {

    @Test("When fetching balances, then free + locked are summed and zero balances are dropped")
    func sumsFreeAndLockedDropsZero() async throws {
        let apiClient = BinanceAPIClient(
            fetchAccount: { [
                BinanceBalance(asset: "BTC", free: "0.4", locked: "0.2"),
                BinanceBalance(asset: "USDT", free: "5000", locked: "0"),
                BinanceBalance(asset: "DUST", free: "0", locked: "0"),
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
            fetchMarginMyTrades: { _, _, _ in [] },
            fetchMarginOpenOrders: { _, _ in [] },
            fetchMarginAllAssets: { [] },
            fetchIsolatedMarginTransfers: { _ in [] }
        )
        let service = BalanceService.live(apiClient: apiClient)

        let balances = try await service.fetchBalances()

        #expect(abs((balances["BTC"] ?? 0) - 0.6) < 1e-9)
        #expect(balances["USDT"] == 5000)
        #expect(balances["DUST"] == nil)
    }
}
