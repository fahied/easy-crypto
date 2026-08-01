//
//  TradePatternSummarizer.swift
//  EasyCrypto
//

import Foundation

/// Reduces a raw trade ledger into a bounded, deterministic `TradeSummary`.
///
/// Pure and AI-free: no network, no I/O beyond reading the supplied trades. Realized
/// P&L reuses the existing `FIFOCalculator` so insights stay consistent with the
/// rest of the app. The resulting `TradeSummary` is the only artifact the on-device
/// model ever sees (ADV-AI-INSIGHTS-002).
nonisolated struct TradePatternSummarizer: Sendable {
    var fifo: FIFOCalculator

    func summarize(_ trades: [Trade], now: Date = Date()) -> TradeSummary {
        guard !trades.isEmpty else { return .empty }

        let chronological = trades.sorted { $0.timestamp < $1.timestamp }

        var bySymbol: [String: [Trade]] = [:]
        for trade in chronological {
            bySymbol[trade.symbol, default: []].append(trade)
        }

        var symbolSummaries: [SymbolSummary] = []
        var totalRealizedPnL: Double = 0
        var sells: [(date: Date, pnl: Double)] = []
        var holdingSpansDays: [Double] = []

        for (symbol, group) in bySymbol {
            let fifoTrades = group.map(Self.toFIFOTrade)
            let result = fifo.calculate(fifoTrades)
            totalRealizedPnL += result.realizedPnL

            let buys = group.lazy.filter(\.isBuyer).count
            symbolSummaries.append(SymbolSummary(
                symbol: symbol,
                asset: group.first?.asset ?? symbol,
                tradeCount: group.count,
                buyCount: buys,
                sellCount: group.count - buys,
                realizedPnL: result.realizedPnL
            ))

            let breakdowns = fifo.saleBreakdowns(fifoTrades)
            for (index, breakdown) in breakdowns.enumerated() {
                if let breakdown {
                    sells.append((group[index].timestamp, breakdown.realizedPnL))
                }
            }

            if let firstBuy = group.first(where: \.isBuyer),
               let lastSell = group.last(where: { !$0.isBuyer }),
               lastSell.timestamp > firstBuy.timestamp {
                holdingSpansDays.append(
                    lastSell.timestamp.timeIntervalSince(firstBuy.timestamp) / 86_400
                )
            }
        }

        let winningSells = sells.lazy.filter { $0.pnl > 0 }.count
        let losingSells = sells.lazy.filter { $0.pnl < 0 }.count

        let orderedSells = sells.sorted { $0.date < $1.date }
        var winStreak = 0
        for sell in orderedSells.reversed() {
            guard sell.pnl > 0 else { break }
            winStreak += 1
        }
        var lossStreak = 0
        for sell in orderedSells.reversed() {
            guard sell.pnl < 0 else { break }
            lossStreak += 1
        }

        let averageHoldingPeriodDays = holdingSpansDays.isEmpty
            ? 0
            : holdingSpansDays.reduce(0, +) / Double(holdingSpansDays.count)

        let ranked = symbolSummaries.sorted {
            $0.realizedPnL != $1.realizedPnL
                ? $0.realizedPnL > $1.realizedPnL
                : $0.tradeCount > $1.tradeCount
        }
        let totalTrades = chronological.count
        let buyCount = chronological.lazy.filter(\.isBuyer).count
        let concentrationRatio = totalTrades > 0
            ? Double(ranked.first?.tradeCount ?? 0) / Double(totalTrades)
            : 0

        return TradeSummary(
            totalTrades: totalTrades,
            buyCount: buyCount,
            sellCount: totalTrades - buyCount,
            symbolCount: bySymbol.count,
            totalRealizedPnL: totalRealizedPnL,
            winningSells: winningSells,
            losingSells: losingSells,
            currentWinStreak: winStreak,
            currentLossStreak: lossStreak,
            averageHoldingPeriodDays: averageHoldingPeriodDays,
            concentrationRatio: concentrationRatio,
            topSymbols: Array(ranked.prefix(TradeSummary.maxSymbols))
        )
    }

    nonisolated private static func toFIFOTrade(_ trade: Trade) -> FIFOTrade {
        FIFOTrade(
            price: trade.price,
            quantity: trade.quantity,
            commission: trade.commission,
            commissionAsset: trade.commissionAsset,
            asset: trade.asset,
            isBuyer: trade.isBuyer
        )
    }
}
