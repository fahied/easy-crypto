//
//  PreviewSampleData.swift
//  EasyCrypto
//

import Foundation
import SwiftData

enum PreviewSampleData {

    @MainActor
    static var container: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Trade.self, SyncMetadata.self, AccountBalance.self, MarginBalance.self,
                 CrossMarginBalance.self,
            configurations: config
        )
        let context = container.mainContext
        for trade in sampleTrades {
            context.insert(trade)
        }
        try? context.save()
        return container
    }

    // MARK: - Sample Trades

    static var sampleTrades: [Trade] {
        [
            // BTC — DCA buys
            Trade(
                binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
                price: 45000, quantity: 0.5, quoteQuantity: 22500,
                commission: 0.0005, commissionAsset: "BTC",
                timestamp: Date(timeIntervalSince1970: 1700000000),
                isBuyer: true, orderId: 100
            ),
            Trade(
                binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
                price: 55000, quantity: 0.3, quoteQuantity: 16500,
                commission: 0.0003, commissionAsset: "BTC",
                timestamp: Date(timeIntervalSince1970: 1705000000),
                isBuyer: true, orderId: 101
            ),
            // BTC — partial sell
            Trade(
                binanceTradeId: 3, symbol: "BTCUSDT", asset: "BTC",
                price: 67000, quantity: 0.2, quoteQuantity: 13400,
                commission: 0.0002, commissionAsset: "BTC",
                timestamp: Date(timeIntervalSince1970: 1710000000),
                isBuyer: false, orderId: 102
            ),
            // ETH — single buy
            Trade(
                binanceTradeId: 4, symbol: "ETHUSDT", asset: "ETH",
                price: 3200, quantity: 5.0, quoteQuantity: 16000,
                commission: 0.005, commissionAsset: "ETH",
                timestamp: Date(timeIntervalSince1970: 1702000000),
                isBuyer: true, orderId: 200
            ),
            // SOL — buy
            Trade(
                binanceTradeId: 5, symbol: "SOLUSDT", asset: "SOL",
                price: 120, quantity: 50.0, quoteQuantity: 6000,
                commission: 0.05, commissionAsset: "SOL",
                timestamp: Date(timeIntervalSince1970: 1708000000),
                isBuyer: true, orderId: 300
            ),
        ]
    }

    // MARK: - Sample Holdings

    static var sampleHoldings: [Holding] {
        [
            Holding(
                asset: "BTC", totalQuantity: 0.6, weightedAvgBuyPrice: 48750,
                totalInvestedUSDT: 29250, currentPrice: 67500, currentValueUSDT: 40500,
                unrealizedPnL: 11250, unrealizedPnLPercent: 38.46, realizedPnL: 4400
            ),
            Holding(
                asset: "ETH", totalQuantity: 5.0, weightedAvgBuyPrice: 3200,
                totalInvestedUSDT: 16000, currentPrice: 3800, currentValueUSDT: 19000,
                unrealizedPnL: 3000, unrealizedPnLPercent: 18.75, realizedPnL: 0
            ),
            Holding(
                asset: "SOL", totalQuantity: 50.0, weightedAvgBuyPrice: 120,
                totalInvestedUSDT: 6000, currentPrice: 155, currentValueUSDT: 7750,
                unrealizedPnL: 1750, unrealizedPnLPercent: 29.17, realizedPnL: 0
            ),
        ]
    }

    static var sampleSummary: PortfolioSummary {
        PortfolioSummary(from: sampleHoldings)
    }

    // MARK: - Sample Klines

    static var sampleKlines: [Kline] {
        (0..<24).map { i in
            let basePrice = 67000.0 + Double(i) * 100
            return Kline(
                openTime: Int64(1700000000 + i * 3600) * 1000,
                open: basePrice,
                high: basePrice + 300,
                low: basePrice - 200,
                close: basePrice + 150,
                volume: Double.random(in: 100...5000),
                closeTime: Int64(1700000000 + (i + 1) * 3600) * 1000
            )
        }
    }
}
