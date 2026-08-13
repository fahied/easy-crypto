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

    /// Enriches each trade with FIFO cost-basis data, computed per asset *and* trading mode
    /// in chronological order (lots never cross modes), then aggregates fills belonging to
    /// the same order (one user order can fill across multiple trades sharing an `orderId`)
    /// into a single transaction. Results from every mode are merged into one list.
    private func buildDetails(from allTrades: [Trade], coin: String?) -> [DayTradeDetail] {
        let byAssetAndMode = Dictionary(grouping: allTrades) {
            AssetModeKey(asset: $0.asset, mode: $0.tradingModeEnum)
        }
        var details: [DayTradeDetail] = []

        for (key, trades) in byAssetAndMode {
            if let coin, coin != key.asset { continue }

            let useMargin = key.mode != .spot
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

            // In margin mode, distribute a per-asset borrowing fee across sells.
            let borrowingFeePerUnit: Double? = useMargin ? estimateBorrowingFeePerUnit(from: chronological) : nil
            let breakdowns: [SaleBreakdown?]
            if let fee = borrowingFeePerUnit, fee != 0 {
                breakdowns = fifoCalculator.saleBreakdownsWithBorrowingFee(fifoTrades, fee)
            } else {
                breakdowns = fifoCalculator.saleBreakdowns(fifoTrades)
            }

            // Pair each fill with its FIFO breakdown, preserving chronological order.
            let fills = Array(zip(chronological, breakdowns))

            // Group fills by order. Buy/sell sides are inherently distinct orders, but we
            // include the side in the key defensively in case an id is ever reused.
            // Multi-day orders must stay split across days so the history tab shows P&L
            // on each fill day rather than collapsing to the latest fill.
            let byOrder = Dictionary(grouping: fills) { fill in
                OrderKey(
                    symbol: fill.0.symbol,
                    orderId: fill.0.orderId,
                    isBuyer: fill.0.isBuyer,
                    mode: fill.0.tradingModeEnum
                )
            }

            for order in byOrder.values {
                // Single-day orders: aggregate all fills together as before.
                // Multi-day orders: produce one entry per day so history isn't lost.
                let calendar = Calendar.current
                let byDay = Dictionary(grouping: order) { fill in
                    calendar.startOfDay(for: fill.0.timestamp)
                }
                for dayFills in byDay.values {
                    details.append(aggregate(fills: dayFills))
                }
            }
        }

        return details.sorted { $0.timestamp > $1.timestamp }
    }

    /// Collapses the fills of a single order on a single day into one `DayTradeDetail`.
    private func aggregate(fills: [(Trade, SaleBreakdown?)]) -> DayTradeDetail {
        let ordered = fills.sorted { $0.0.timestamp < $1.0.timestamp }
        let first = ordered[0].0
        let totalQuantity = ordered.reduce(0) { $0 + $1.0.quantity }
        let totalQuote = ordered.reduce(0) { $0 + $1.0.quoteQuantity }
        let avgPrice = totalQuantity > 0 ? totalQuote / totalQuantity : first.price
        let timestamp = ordered.map(\.0.timestamp).max() ?? first.timestamp
        let day = Calendar.current.startOfDay(for: timestamp)
        let dayStr = ISO8601DateFormatter().string(from: day)

        if first.isBuyer {
            return DayTradeDetail(
                id: "\(first.symbol)-\(first.tradingMode)-order-\(first.orderId)-buy-\(dayStr)",
                asset: first.asset,
                symbol: first.symbol,
                timestamp: timestamp,
                isBuyer: true,
                tradingMode: first.tradingModeEnum,
                price: avgPrice,
                quantity: totalQuantity,
                total: totalQuote,
                costBasisPrice: nil,
                invested: totalQuote,
                realizedPnL: nil,
                borrowingFee: nil,
                marginAdjustedPnL: nil
            )
        }

        let costBasisAmount = ordered.reduce(0.0) { $0 + ($1.1?.costBasisAmount ?? 0) }
        let realizedPnL = ordered.reduce(0.0) { $0 + ($1.1?.realizedPnL ?? 0) }
        let borrowingFee = ordered.reduce(0.0) { $0 + ($1.1?.borrowingFee ?? 0) }
        let marginAdjustedPnL = borrowingFee != 0 ? realizedPnL - borrowingFee : nil
        let costBasisPrice = totalQuantity > 0 ? costBasisAmount / totalQuantity : nil
        return DayTradeDetail(
            id: "\(first.symbol)-\(first.tradingMode)-order-\(first.orderId)-sell-\(dayStr)",
            asset: first.asset,
            symbol: first.symbol,
            timestamp: timestamp,
            isBuyer: false,
            tradingMode: first.tradingModeEnum,
            price: avgPrice,
            quantity: totalQuantity,
            total: totalQuote,
            costBasisPrice: costBasisPrice,
            invested: costBasisAmount,
            realizedPnL: realizedPnL,
            borrowingFee: borrowingFee,
            marginAdjustedPnL: marginAdjustedPnL
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

    /// Estimates a per-unit borrowing fee for a single asset/mode group.
    ///
    /// In cross-margin mode, fees come from the asset's interest rate in
    /// `CrossMarginAccountData.perAssetInterest`. In isolated-margin mode, from
    /// `IsolatedMarginBalance.interest`. For trade history (which reads persisted
    /// data), we use a rough approximation: total commission on sells divided by
    /// total sell quantity, which captures the realized borrowing cost already
    /// embedded in the trades.
    ///
    /// `trades` should be the full chronological trade list for the asset/mode group
    /// (not the display-filtered subset), so the estimate is stable across
    /// coin-filter changes.
    private func estimateBorrowingFeePerUnit(from trades: [Trade]) -> Double? {
        let sells = trades.filter { !$0.isBuyer }
        let totalFee = sells.reduce(0.0) { $0 + $1.commission }
        let totalQty = sells.reduce(0.0) { $0 + $1.quantity }
        guard totalQty > 0 else { return nil }
        return totalFee / totalQty
    }
}

/// Identifies an independent FIFO lot chain: lots never cross assets or trading modes.
private struct AssetModeKey: Hashable {
    let asset: String
    let mode: TradingMode
}

/// Identifies a single user order so its individual fills can be aggregated.
private struct OrderKey: Hashable {
    let symbol: String
    let orderId: Int64
    let isBuyer: Bool
    let mode: TradingMode
}
