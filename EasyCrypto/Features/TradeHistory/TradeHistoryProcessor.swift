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

    /// Enriches each trade with FIFO cost-basis data, computed per asset in chronological order.
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

            for (index, trade) in chronological.enumerated() {
                let breakdown = breakdowns[index]
                details.append(DayTradeDetail(
                    id: "\(trade.symbol)-\(trade.binanceTradeId)",
                    asset: trade.asset,
                    symbol: trade.symbol,
                    timestamp: trade.timestamp,
                    isBuyer: trade.isBuyer,
                    price: trade.price,
                    quantity: trade.quantity,
                    total: trade.quoteQuantity,
                    costBasisPrice: breakdown?.costBasisPrice,
                    invested: trade.isBuyer ? trade.quoteQuantity : breakdown?.costBasisAmount,
                    realizedPnL: breakdown?.realizedPnL
                ))
            }
        }

        return details.sorted { $0.timestamp > $1.timestamp }
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
