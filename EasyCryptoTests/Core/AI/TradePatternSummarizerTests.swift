//
//  TradePatternSummarizerTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
@testable import EasyCrypto

@Suite("Given the TradePatternSummarizer")
@MainActor
struct TradePatternSummarizerTests {

    private let summarizer = TradePatternSummarizer(fifo: .live)
    private let day: TimeInterval = 86_400

    private func trade(
        id: Int64,
        symbol: String,
        asset: String,
        price: Double,
        quantity: Double = 1,
        isBuyer: Bool,
        at offsetDays: Double
    ) -> Trade {
        Trade(
            binanceTradeId: id,
            symbol: symbol,
            asset: asset,
            price: price,
            quantity: quantity,
            quoteQuantity: price * quantity,
            commission: 0,
            commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: offsetDays * day),
            isBuyer: isBuyer,
            orderId: id
        )
    }

    @Test("When the ledger is empty, then the summary is empty")
    func emptyLedger() {
        #expect(summarizer.summarize([], now: Date(timeIntervalSince1970: 0)) == .empty)
    }

    @Test("When trades span two symbols, then aggregates, P&L, and streaks are correct")
    func aggregatesAcrossSymbols() {
        // BTC: buy @100, sell @120 -> +20 (winning). ETH: buy @50, sell @40 -> -10 (losing, last).
        let trades = [
            trade(id: 1, symbol: "BTCUSDT", asset: "BTC", price: 100, isBuyer: true, at: 1),
            trade(id: 2, symbol: "BTCUSDT", asset: "BTC", price: 120, isBuyer: false, at: 2),
            trade(id: 3, symbol: "ETHUSDT", asset: "ETH", price: 50, isBuyer: true, at: 3),
            trade(id: 4, symbol: "ETHUSDT", asset: "ETH", price: 40, isBuyer: false, at: 4),
        ]

        let summary = summarizer.summarize(trades, now: Date(timeIntervalSince1970: 5 * day))

        #expect(summary.totalTrades == 4)
        #expect(summary.buyCount == 2)
        #expect(summary.sellCount == 2)
        #expect(summary.symbolCount == 2)
        #expect(abs(summary.totalRealizedPnL - 10) < 1e-9)
        #expect(summary.winningSells == 1)
        #expect(summary.losingSells == 1)
        // Most recent sell (ETH @40) lost -> trailing loss streak of 1, no win streak.
        #expect(summary.currentLossStreak == 1)
        #expect(summary.currentWinStreak == 0)
        // Each symbol has 2 of 4 trades.
        #expect(abs(summary.concentrationRatio - 0.5) < 1e-9)
        #expect(summary.topSymbols.count == 2)
        // Holding span: BTC 1 day, ETH 1 day -> average 1 day.
        #expect(abs(summary.averageHoldingPeriodDays - 1) < 1e-9)
    }

    @Test("When two profitable sells are most recent, then the win streak counts them")
    func trailingWinStreak() {
        let trades = [
            trade(id: 1, symbol: "BTCUSDT", asset: "BTC", price: 100, isBuyer: true, at: 1),
            trade(id: 2, symbol: "BTCUSDT", asset: "BTC", price: 90, isBuyer: false, at: 2),  // -10 lose
            trade(id: 3, symbol: "ETHUSDT", asset: "ETH", price: 50, isBuyer: true, at: 3),
            trade(id: 4, symbol: "ETHUSDT", asset: "ETH", price: 60, isBuyer: false, at: 4),  // +10 win
            trade(id: 5, symbol: "SOLUSDT", asset: "SOL", price: 20, isBuyer: true, at: 5),
            trade(id: 6, symbol: "SOLUSDT", asset: "SOL", price: 25, isBuyer: false, at: 6),  // +5 win
        ]

        let summary = summarizer.summarize(trades, now: Date(timeIntervalSince1970: 7 * day))

        #expect(summary.winningSells == 2)
        #expect(summary.losingSells == 1)
        #expect(summary.currentWinStreak == 2)
        #expect(summary.currentLossStreak == 0)
    }

    @Test("When there are more symbols than the cap, then topSymbols stays bounded")
    func boundedTopSymbols() {
        let trades = (0..<25).map { index in
            trade(
                id: Int64(index),
                symbol: "SYM\(index)USDT",
                asset: "SYM\(index)",
                price: 100,
                isBuyer: true,
                at: Double(index)
            )
        }

        let summary = summarizer.summarize(trades, now: Date(timeIntervalSince1970: 0))

        #expect(summary.totalTrades == 25)
        #expect(summary.symbolCount == 25)
        #expect(summary.topSymbols.count == TradeSummary.maxSymbols)
        #expect(abs(summary.concentrationRatio - (1.0 / 25.0)) < 1e-9)
    }

    @Test("When cap is exceeded, topSymbols includes the most profitable symbols by P&L not trade count")
    func topSymbolsRankedByPnL() {
        let day: TimeInterval = 86_400

        // SYM1: 2 trades, buy @100 sell @600 -> +500 PnL (most profitable, fewest trades)
        let sym1Trades = [
            trade(id: 1, symbol: "SYM1USDT", asset: "SYM1", price: 100, isBuyer: true, at: 1),
            trade(id: 2, symbol: "SYM1USDT", asset: "SYM1", price: 600, isBuyer: false, at: 2),
        ]

        // SYM2..SYM11: 12 trades each (buy@100 sell@101 -> +1 each), more trades than SYM1
        let otherTrades = (2...11).flatMap { symIndex -> [Trade] in
            let baseId = Int64((symIndex - 2) * 12 + 3)
            return (0..<12).map { i ->
                trade(
                    id: baseId + Int64(i),
                    symbol: "SYM\(symIndex)USDT",
                    asset: "SYM\(symIndex)",
                    price: i % 2 == 0 ? 100 : 101,
                    isBuyer: i % 2 == 0,
                    at: Double(i) + 3
                )
            }
        }

        let trades = sym1Trades + otherTrades
        let summary = summarizer.summarize(trades, now: Date(timeIntervalSince1970: 30 * day))

        #expect(summary.topSymbols.count == TradeSummary.maxSymbols)

        let topSymbolNames = summary.topSymbols.map(\.symbol)
        // SYM1 (+500 PnL) must be in the top 10 even though it has only 2 trades
        #expect(topSymbolNames.contains("SYM1USDT"), "SYM1USDT (+500 PnL) should be in topSymbols but was excluded")
        // The entry for SYM1 should be first (highest PnL)
        #expect(topSymbolNames.first == "SYM1USDT")
    }
}
