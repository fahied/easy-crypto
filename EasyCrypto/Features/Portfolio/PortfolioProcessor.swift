//
//  PortfolioProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation
import os

@Observable
class PortfolioProcessor: Processor {
    var state = PortfolioState()

    private let tradeImportService: TradeImportService
    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator
    private let balanceService: BalanceService
    private let modelContext: ModelContext

    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "portfolio"
    )

    init(
        tradeImportService: TradeImportService,
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer,
        balanceService: BalanceService = .noop
    ) {
        self.tradeImportService = tradeImportService
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.balanceService = balanceService
        self.modelContext = ModelContext(modelContainer)
    }

    func handle(_ intent: PortfolioIntent) async {
        switch intent {
        case .refresh:
            await refresh()
        case .sortHoldings(let criteria):
            state.sortCriteria = criteria
            state.holdings = Self.sortHoldings(state.holdings, by: criteria)
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        state.isLoading = true
        state.error = nil

        do {
            // 1. Read existing sync metadata
            let syncDescriptor = FetchDescriptor<SyncMetadata>()
            let existingMetadata = try modelContext.fetch(syncDescriptor)
            let syncMap = Dictionary(
                uniqueKeysWithValues: existingMetadata.map { ($0.symbol, $0.lastTradeId) }
            )

            // 2. Import trades from Binance
            let importResult = try await tradeImportService.sync(syncMap)

            // 3. Persist new trades
            for mapped in importResult.mappedTrades {
                let trade = Trade(
                    binanceTradeId: mapped.binanceTradeId,
                    symbol: mapped.symbol,
                    asset: mapped.asset,
                    price: mapped.price,
                    quantity: mapped.quantity,
                    quoteQuantity: mapped.quoteQuantity,
                    commission: mapped.commission,
                    commissionAsset: mapped.commissionAsset,
                    timestamp: mapped.timestamp,
                    isBuyer: mapped.isBuyer,
                    orderId: mapped.orderId
                )
                modelContext.insert(trade)
            }

            // 4. Update sync metadata
            for update in importResult.syncUpdates {
                let symbol = update.symbol
                let predicate = #Predicate<SyncMetadata> { $0.symbol == symbol }
                var descriptor = FetchDescriptor<SyncMetadata>(predicate: predicate)
                descriptor.fetchLimit = 1

                if let existing = try modelContext.fetch(descriptor).first {
                    existing.lastTradeId = update.lastTradeId
                    existing.lastSyncDate = update.syncDate
                } else {
                    modelContext.insert(SyncMetadata(
                        symbol: update.symbol,
                        lastTradeId: update.lastTradeId,
                        lastSyncDate: update.syncDate
                    ))
                }
            }

            try modelContext.save()

            // 5. Compute holdings from all persisted trades
            let portfolioData = try await computePortfolioData()
            state.holdings = Self.sortHoldings(portfolioData.holdings, by: state.sortCriteria)
            state.summary = PortfolioSummary(
                from: state.holdings,
                totalRealizedPnL: portfolioData.totalRealizedPnL
            )
            state.lastRefreshDate = Date()

            let count = state.holdings.count
            Self.logger.info("Portfolio refreshed: \(count) holdings")
        } catch {
            state.error = error.localizedDescription
            let desc = error.localizedDescription
            Self.logger.error("Portfolio refresh failed: \(desc)")
        }

        state.isLoading = false
    }

    // MARK: - Holdings Computation

    private struct PortfolioData {
        let holdings: [Holding]
        let totalRealizedPnL: Double
    }

    private func computePortfolioData() async throws -> PortfolioData {
        let tradesDescriptor = FetchDescriptor<Trade>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allTrades = try modelContext.fetch(tradesDescriptor)
        let tradesByAsset = Dictionary(grouping: allTrades) { $0.asset }

        // FIFO per traded asset — cost basis + realized P&L (across all history,
        // including fully-closed positions).
        var fifoByAsset: [String: FIFOResult] = [:]
        var totalRealizedPnL: Double = 0
        for (asset, trades) in tradesByAsset {
            let result = fifoCalculator.calculate(trades.map(Self.toFIFOTrade))
            fifoByAsset[asset] = result
            totalRealizedPnL += result.realizedPnL
        }

        // Authoritative wallet balances drive the displayed quantity. On failure,
        // fall back to the last persisted balances so the UI degrades gracefully.
        let balances: [String: Double]
        do {
            let live = try await balanceService.fetchBalances()
            try persistBalances(live)
            balances = live
        } catch {
            let persisted = try modelContext.fetch(FetchDescriptor<AccountBalance>())
            balances = Dictionary(persisted.map { ($0.asset, $0.quantity) }, uniquingKeysWith: { first, _ in first })
        }

        // Prices for non-USDT balance assets (USDT is valued 1:1).
        let priceSymbols = balances.keys.filter { $0 != "USDT" }.map { "\($0)USDT" }
        let prices = try await priceService.fetchPrices(priceSymbols)

        var holdings: [Holding] = []
        for (asset, quantity) in balances where quantity > 0 {
            let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
            holdings.append(HoldingFactory.make(
                asset: asset,
                quantity: quantity,
                currentPrice: currentPrice,
                fifo: fifoByAsset[asset] ?? .empty
            ))
        }

        return PortfolioData(holdings: holdings, totalRealizedPnL: totalRealizedPnL)
    }

    /// Replaces the persisted balance snapshot so the Holdings tab can read it offline.
    private func persistBalances(_ balances: [String: Double]) throws {
        try modelContext.delete(model: AccountBalance.self)
        let now = Date()
        for (asset, quantity) in balances where quantity > 0 {
            modelContext.insert(AccountBalance(asset: asset, quantity: quantity, updatedAt: now))
        }
        try modelContext.save()
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

    // MARK: - Sorting

    private static func sortHoldings(_ holdings: [Holding], by criteria: SortCriteria) -> [Holding] {
        switch criteria {
        case .value:
            holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        case .name:
            holdings.sorted { $0.asset < $1.asset }
        case .pnl:
            holdings.sorted { $0.unrealizedPnL > $1.unrealizedPnL }
        case .pnlPercent:
            holdings.sorted { $0.unrealizedPnLPercent > $1.unrealizedPnLPercent }
        }
    }
}
