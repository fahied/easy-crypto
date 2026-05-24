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
    private let modelContext: ModelContext

    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "portfolio"
    )

    init(
        tradeImportService: TradeImportService,
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer
    ) {
        self.tradeImportService = tradeImportService
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
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

        // Fetch current prices
        let symbols = tradesByAsset.keys.map { "\($0)USDT" }
        let prices = try await priceService.fetchPrices(symbols)

        var holdings: [Holding] = []
        var totalRealizedPnL: Double = 0

        for (asset, trades) in tradesByAsset {
            let fifoTrades = trades.map { trade in
                FIFOTrade(
                    price: trade.price,
                    quantity: trade.quantity,
                    commission: trade.commission,
                    commissionAsset: trade.commissionAsset,
                    asset: trade.asset,
                    isBuyer: trade.isBuyer
                )
            }

            let fifoResult = fifoCalculator.calculate(fifoTrades)
            totalRealizedPnL += fifoResult.realizedPnL

            guard fifoResult.totalRemainingQuantity > 0 else { continue }

            let currentPrice = prices["\(asset)USDT"] ?? 0
            let currentValue = fifoResult.totalRemainingQuantity * currentPrice
            let unrealizedPnL = currentValue - fifoResult.totalInvestedUSDT
            let unrealizedPnLPercent = fifoResult.totalInvestedUSDT > 0
                ? (unrealizedPnL / fifoResult.totalInvestedUSDT) * 100
                : 0

            holdings.append(Holding(
                asset: asset,
                totalQuantity: fifoResult.totalRemainingQuantity,
                weightedAvgBuyPrice: fifoResult.weightedAvgBuyPrice,
                totalInvestedUSDT: fifoResult.totalInvestedUSDT,
                currentPrice: currentPrice,
                currentValueUSDT: currentValue,
                unrealizedPnL: unrealizedPnL,
                unrealizedPnLPercent: unrealizedPnLPercent,
                realizedPnL: fifoResult.realizedPnL
            ))
        }

        return PortfolioData(holdings: holdings, totalRealizedPnL: totalRealizedPnL)
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
