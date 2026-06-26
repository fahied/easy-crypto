//
//  TradeHistoryProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class TradeHistoryProcessor: Processor {
    var state = TradeHistoryState()

    private let modelContext: ModelContext
    private let fifoCalculator: FIFOCalculator
    private let calendar = Calendar.current

    init(modelContainer: ModelContainer, fifoCalculator: FIFOCalculator = .live) {
        self.modelContext = ModelContext(modelContainer)
        self.fifoCalculator = fifoCalculator
    }

    func handle(_ intent: TradeHistoryIntent) async {
        switch intent {
        case .loadHistory:
            await loadHistory()
        case .filterByCoin(let coin):
            await filterByCoin(coin)
        case .nextMonth:
            shiftMonth(by: 1)
        case .previousMonth:
            shiftMonth(by: -1)
        }
    }

    /// Returns the day's transactions (reverse chronological) for the active filter.
    func details(on date: Date) -> [DayTradeDetail] {
        let day = calendar.startOfDay(for: date)
        return state.details.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
    }

    // MARK: - Intent Handlers

    private func loadHistory() async {
        state.isLoading = true
        state.error = nil

        do {
            let allTrades = try fetchAllTrades()
            state.availableCoins = discoverCoins(from: allTrades)
            rebuild(from: allTrades, coin: state.selectedCoin)

            // Default the calendar to the month of the most recent trade.
            if let latest = allTrades.last {
                state.displayedMonth = calendar.startOfMonth(for: latest.timestamp)
            }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    private func filterByCoin(_ coin: String?) async {
        state.selectedCoin = coin
        state.error = nil

        do {
            let allTrades = try fetchAllTrades()
            rebuild(from: allTrades, coin: coin)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func shiftMonth(by months: Int) {
        guard let shifted = calendar.date(
            byAdding: .month,
            value: months,
            to: state.displayedMonth
        ) else { return }
        state.displayedMonth = calendar.startOfMonth(for: shifted)
    }

    // MARK: - Building

    /// Recomputes `trades`, `details`, and `dailyPnL` for the given coin filter.
    private func rebuild(from allTrades: [Trade], coin: String?) {
        let filtered = coin == nil ? allTrades : allTrades.filter { $0.asset == coin }
        state.trades = filtered.sorted { $0.timestamp > $1.timestamp }

        let details = buildDetails(from: allTrades, coin: coin)
        state.details = details
        state.dailyPnL = buildDailyPnL(from: details)
    }

    /// Enriches each trade with FIFO cost-basis data, computed per asset in chronological
    /// order, then aggregates fills belonging to the same order (one user order can fill
    /// across multiple trades sharing an `orderId`) into a single transaction.
    private func buildDetails(from allTrades: [Trade], coin: String?) -> [DayTradeDetail] {
        let byAsset = Dictionary(grouping: allTrades) { $0.asset }
        var details: [DayTradeDetail] = []

        for (asset, trades) in byAsset {
            if let coin, coin != asset { continue }

            let chronological = trades.sorted { $0.timestamp < $1.timestamp }
            let fifoTrades = chronological.map { trade in
                FIFOTrade(
                    price: trade.price,
                    quantity: trade.quantity,
                    commission: trade.commission,
                    commissionAsset: trade.commissionAsset,
                    asset: trade.asset,
                    isBuyer: trade.isBuyer
                )
            }
            let breakdowns = fifoCalculator.saleBreakdowns(fifoTrades)

            // Pair each fill with its FIFO breakdown, preserving chronological order.
            let fills = Array(zip(chronological, breakdowns))

            // Group fills by order. Buy/sell sides are inherently distinct orders, but we
            // include the side in the key defensively in case an id is ever reused.
            let byOrder = Dictionary(grouping: fills) { fill in
                OrderKey(symbol: fill.0.symbol, orderId: fill.0.orderId, isBuyer: fill.0.isBuyer)
            }

            for order in byOrder.values {
                details.append(aggregate(fills: order))
            }
        }

        return details.sorted { $0.timestamp > $1.timestamp }
    }

    /// Collapses the fills of a single order into one `DayTradeDetail` with summed
    /// quantities/totals and a quantity-weighted average execution price.
    private func aggregate(fills: [(Trade, SaleBreakdown?)]) -> DayTradeDetail {
        let ordered = fills.sorted { $0.0.timestamp < $1.0.timestamp }
        let first = ordered[0].0
        let totalQuantity = ordered.reduce(0) { $0 + $1.0.quantity }
        let totalQuote = ordered.reduce(0) { $0 + $1.0.quoteQuantity }
        let avgPrice = totalQuantity > 0 ? totalQuote / totalQuantity : first.price
        let timestamp = ordered.map(\.0.timestamp).max() ?? first.timestamp

        if first.isBuyer {
            return DayTradeDetail(
                id: "\(first.symbol)-order-\(first.orderId)-buy",
                asset: first.asset,
                symbol: first.symbol,
                timestamp: timestamp,
                isBuyer: true,
                price: avgPrice,
                quantity: totalQuantity,
                total: totalQuote,
                costBasisPrice: nil,
                invested: totalQuote,
                realizedPnL: nil
            )
        }

        let costBasisAmount = ordered.reduce(0.0) { $0 + ($1.1?.costBasisAmount ?? 0) }
        let realizedPnL = ordered.reduce(0.0) { $0 + ($1.1?.realizedPnL ?? 0) }
        let costBasisPrice = totalQuantity > 0 ? costBasisAmount / totalQuantity : nil
        return DayTradeDetail(
            id: "\(first.symbol)-order-\(first.orderId)-sell",
            asset: first.asset,
            symbol: first.symbol,
            timestamp: timestamp,
            isBuyer: false,
            price: avgPrice,
            quantity: totalQuantity,
            total: totalQuote,
            costBasisPrice: costBasisPrice,
            invested: costBasisAmount,
            realizedPnL: realizedPnL
        )
    }

    private func buildDailyPnL(from details: [DayTradeDetail]) -> [Date: DailyPnL] {
        let grouped = Dictionary(grouping: details) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.mapValues { dayTrades in
            let sells = dayTrades.filter { !$0.isBuyer }
            return DailyPnL(
                date: calendar.startOfDay(for: dayTrades[0].timestamp),
                realizedPnL: sells.compactMap(\.realizedPnL).reduce(0, +),
                sellCount: sells.count,
                tradeCount: dayTrades.count
            )
        }
    }

    // MARK: - Fetching

    private func fetchAllTrades() throws -> [Trade] {
        let descriptor = FetchDescriptor<Trade>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func discoverCoins(from trades: [Trade]) -> [String] {
        Array(Set(trades.map(\.asset))).sorted()
    }
}

/// Identifies a single user order so its individual fills can be aggregated.
private struct OrderKey: Hashable {
    let symbol: String
    let orderId: Int64
    let isBuyer: Bool
}
