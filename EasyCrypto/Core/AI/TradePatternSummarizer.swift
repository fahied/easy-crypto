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

            var lotQueue: [(timestamp: Date, quantity: Double)] = []
            var remainingSellQty: Double = 0
            for (index, trade) in group.enumerated() {
                if trade.isBuyer {
                    if remainingSellQty > 0 {
                        // This buy arrived while a sell was still pending — allocate to
                        // outstanding sell quantity first (handles commission-in-base buys
                        // that were partially consumed by a prior sell's fee adjustment).
                        if remainingSellQty >= trade.quantity {
                            remainingSellQty -= trade.quantity
                        } else {
                            lotQueue.append((timestamp: trade.timestamp, quantity: trade.quantity - remainingSellQty))
                            remainingSellQty = 0
                        }
                    } else {
                        lotQueue.append((timestamp: trade.timestamp, quantity: trade.quantity))
                    }
                } else if let breakdown {
                    let feeInBase = trade.commissionAsset == trade.asset ? trade.commission : 0
                    remainingSellQty = trade.quantity + feeInBase
                    var weightedTimestampSum: Double = 0
                    var weightedQtySum: Double = 0

                    while remainingSellQty > 1e-12 && !lotQueue.isEmpty {
                        let consumed = min(lotQueue[0].quantity, remainingSellQty)
                        weightedTimestampSum += lotQueue[0].timestamp.timeIntervalSince1970 * consumed
                        weightedQtySum += consumed
                        remainingSellQty -= consumed
                        lotQueue[0].quantity -= consumed
                        if lotQueue[0].quantity <= 1e-12 {
                            lotQueue.removeFirst()
                        }
                    }
                    if weightedQtySum > 1e-12 {
                        let avgBuyTimestamp = weightedTimestampSum / weightedQtySum
                        holdingSpansDays.append(
                            (trade.timestamp.timeIntervalSince1970 - avgBuyTimestamp) / 86_400
                        )
                    }
                }
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
