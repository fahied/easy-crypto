//
//  PortfolioProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class PortfolioProcessor: Processor {
    var state = PortfolioState()

    private let tradeImportService: TradeImportService
    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator
    private let balanceService: BalanceService
    private let modelContext: ModelContext

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

    // MARK: - Intent Handler

    func handle(_ intent: PortfolioIntent) async {
        switch intent {
        case .refresh:
            await refresh()
        case .sortHoldings(let by):
            state.sortBy = by
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        state.isLoading = true
        state.error = nil

        do {
            let syncMap = fetchSyncMap()
            let importResult = try await tradeImportService.sync(syncMap)

            persistSyncUpdates(importResult.syncUpdates)
            try persistTrades(importResult.mappedTrades)

            state.summary = try await computeSummary()
            state.lastRefreshDate = Date()
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Summary Computation

    private func computeSummary() async throws -> PortfolioSummary {
        let allTrades = try fetchAllTrades()
        let balances = try await balanceService.fetchBalances()

        let tradesByAsset = Dictionary(grouping: allTrades.map(Self.toFIFOTrade)) { $0.asset }
        var fifoByAsset: [String: FIFOResult] = [:]
        var totalRealizedPnL: Double = 0

        for (asset, assetTrades) in tradesByAsset {
            let result = fifoCalculator.calculate(assetTrades)
            fifoByAsset[asset] = result
            totalRealizedPnL += result.realizedPnL
        }

        let dustThreshold = 0.001
        let priceAssets = balances.keys.filter { $0 != "USDT" && balances[$0] ?? 0 >= dustThreshold }
        let priceSymbols = priceAssets.map { "\($0)USDT" }
        let prices = try await priceService.fetchPrices(priceSymbols)

        var holdings: [Holding] = []
        for (asset, quantity) in balances where quantity >= dustThreshold {
            let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
            let fifoResult = fifoByAsset[asset] ?? .empty
            holdings.append(HoldingFactory.make(
                asset: asset,
                quantity: quantity,
                currentPrice: currentPrice,
                fifo: fifoResult
            ))
        }

        return PortfolioSummary(from: holdings, totalRealizedPnL: totalRealizedPnL)
    }

    // MARK: - Data Access Helpers

    private func fetchSyncMap() -> [String: Int64] {
        let descriptor = FetchDescriptor<SyncMetadata>()
        guard let metadata = try? modelContext.fetch(descriptor) else { return [:] }
        return Dictionary(metadata.map { ($0.symbol, $0.lastTradeId) }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchAllTrades() throws -> [Trade] {
        let descriptor = FetchDescriptor<Trade>(sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Persistence Helpers

    private func persistSyncUpdates(_ updates: [SyncUpdate]) {
        for update in updates {
            let entity = SyncMetadata(
                symbol: update.symbol,
                lastTradeId: update.lastTradeId,
                lastSyncDate: Date()
            )
            modelContext.insert(entity)
        }
        try? modelContext.save()
    }

    private func persistTrades(_ mappedTrades: [MappedTrade]) throws {
        for mapped in mappedTrades {
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
                orderId: mapped.orderId,
                tradingMode: .spot
            )
            modelContext.insert(trade)
        }
        try modelContext.save()
    }

    // MARK: - Trade Mapping

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
