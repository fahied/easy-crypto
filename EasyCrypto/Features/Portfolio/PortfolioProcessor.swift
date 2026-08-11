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
    private let marginTradeImportService: MarginTradeImportService
    private let marginBalanceService: MarginBalanceService
    private let modelContext: ModelContext

    init(
        tradeImportService: TradeImportService,
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer,
        balanceService: BalanceService = .noop,
        marginTradeImportService: MarginTradeImportService = .noop,
        marginBalanceService: MarginBalanceService = .noop
    ) {
        self.tradeImportService = tradeImportService
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.balanceService = balanceService
        self.marginTradeImportService = marginTradeImportService
        self.marginBalanceService = marginBalanceService
        self.modelContext = ModelContext(modelContainer)
    }

    // MARK: - Intent Handler

    func handle(_ intent: PortfolioIntent) async {
        switch intent {
        case .refresh:
            await refresh()
        case .loadPersisted:
            await loadPersistedData()
        case .sortHoldings(let by):
            state.sortBy = by
        case .selectTab:
            break
        }
    }

    // MARK: - Load from Persisted Data

    /// Builds the portfolio summary from SwiftData only — no exchange sync.
    /// Used on launch to show cached data immediately.
    private func loadPersistedData() async {
        state.isLoading = true
        state.error = nil

        do {
            let spotBalances = fetchPersistedSpotBalances()
            state.summary = try await computeSummary(persistedSpotBalances: spotBalances)
            state.lastRefreshDate = Date()
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Refresh

    private func refresh() async {
        state.isLoading = true
        state.error = nil

        do {
            // Sync spot trades (incremental, from last cursor)
            let spotSyncMap = fetchSyncMap()
            let spotImport = try await tradeImportService.sync(spotSyncMap)
            persistSyncUpdates(spotImport.syncUpdates)
            try persistTrades(spotImport.mappedTrades, mode: .spot)

            // Sync margin trades for cross-margin and isolated-margin in parallel
            let marginSyncMap = fetchSyncMap()
            async let crossImport = marginTradeImportService.sync(.crossMargin, marginSyncMap)
            async let isolatedImport = marginTradeImportService.sync(.isolatedMargin, marginSyncMap)

            let crossResult = try await crossImport
            let isolatedResult = try await isolatedImport

            persistSyncUpdates(crossResult.syncUpdates)
            try persistTrades(crossResult.mappedTrades, mode: .crossMargin)
            try await persistCrossMarginBalances()

            persistSyncUpdates(isolatedResult.syncUpdates)
            try persistTrades(isolatedResult.mappedTrades, mode: .isolatedMargin)

            state.summary = try await computeSummary()
            state.lastRefreshDate = Date()
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Summary Computation

    private func computeSummary(
        persistedSpotBalances: [String: Double]? = nil
    ) async throws -> PortfolioSummary {
        let spotHoldings = try await computeSpotHoldings(persistedBalances: persistedSpotBalances)
        let crossHoldings = try await computeCrossMarginHoldings()
        let isolatedHoldings = try computeIsolatedMarginHoldings()

        let spotSummary = PortfolioSummary(from: spotHoldings)
        let crossSummary = PortfolioSummary(from: crossHoldings)
        let isolatedSummary = PortfolioSummary(from: isolatedHoldings)

        let allHoldings = spotHoldings + crossHoldings + isolatedHoldings

        let totalInvested = allHoldings.reduce(0.0) { $0 + $1.totalInvestedUSDT }
        let totalCurrent = allHoldings.reduce(0.0) { $0 + $1.currentValueUSDT }
        let totalUnrealized = allHoldings.reduce(0.0) { $0 + $1.unrealizedPnL }
        let totalRealized = allHoldings.reduce(0.0) { $0 + $1.realizedPnL }
        let totalInvestedCalc = totalInvested > 0 ? (totalUnrealized / totalInvested) * 100.0 : 0.0
        let count = allHoldings.count

        return PortfolioSummary(
            totalInvestedUSDT: totalInvested,
            totalCurrentValueUSDT: totalCurrent,
            totalUnrealizedPnL: totalUnrealized,
            totalUnrealizedPnLPercent: totalInvestedCalc,
            totalRealizedPnL: totalRealized,
            holdingsCount: count,
            spot: PortfolioSummary.ModeSummary(
                investedUSDT: spotSummary.totalInvestedUSDT,
                currentValueUSDT: spotSummary.totalCurrentValueUSDT,
                unrealizedPnL: spotSummary.totalUnrealizedPnL,
                unrealizedPnLPercent: spotSummary.totalUnrealizedPnLPercent,
                realizedPnL: spotSummary.totalRealizedPnL,
                holdingsCount: spotSummary.holdingsCount
            ),
            crossMargin: PortfolioSummary.ModeSummary(
                investedUSDT: crossSummary.totalInvestedUSDT,
                currentValueUSDT: crossSummary.totalCurrentValueUSDT,
                unrealizedPnL: crossSummary.totalUnrealizedPnL,
                unrealizedPnLPercent: crossSummary.totalUnrealizedPnLPercent,
                realizedPnL: crossSummary.totalRealizedPnL,
                holdingsCount: crossSummary.holdingsCount
            ),
            isolatedMargin: PortfolioSummary.ModeSummary(
                investedUSDT: isolatedSummary.totalInvestedUSDT,
                currentValueUSDT: isolatedSummary.totalCurrentValueUSDT,
                unrealizedPnL: isolatedSummary.totalUnrealizedPnL,
                unrealizedPnLPercent: isolatedSummary.totalUnrealizedPnLPercent,
                realizedPnL: isolatedSummary.totalRealizedPnL,
                holdingsCount: isolatedSummary.holdingsCount
            )
        )
    }

    // MARK: - Spot Holdings

    private func computeSpotHoldings(
        persistedBalances: [String: Double]? = nil
    ) async throws -> [Holding] {
        let allTrades = try fetchTrades(mode: .spot)
        guard !allTrades.isEmpty else { return [] }

        let balances: [String: Double]
        if let persisted = persistedBalances {
            balances = persisted
        } else {
            balances = try await balanceService.fetchBalances()
        }
        let tradesByAsset = Dictionary(grouping: allTrades.map(Self.toFIFOTrade)) { $0.asset }

        var fifoByAsset: [String: FIFOResult] = [:]
        var totalRealizedPnL: Double = 0
        for (asset, assetTrades) in tradesByAsset {
            let result = fifoCalculator.calculate(assetTrades)
            fifoByAsset[asset] = result
            totalRealizedPnL += result.realizedPnL
        }

        // Include all assets that ever appeared in spot trades, not just active ones
        let tradeAssets = Set(tradesByAsset.keys)
        let balanceAssets = Set(balances.keys)
        let allAssets = tradeAssets.union(balanceAssets)

        let priceAssets = allAssets.filter { $0 != "USDT" && PriceCatalog.symbols.contains($0) }
        let priceSymbols = priceAssets.map { "\($0)USDT" }
        let prices = try await priceService.fetchPrices(priceSymbols)

        return allAssets.sorted().compactMap { asset in
            let quantity = balances[asset] ?? 0
            let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
            let fifoResult = fifoByAsset[asset] ?? .empty

            if quantity == 0 && fifoResult.remainingLots.isEmpty { return nil }

            return HoldingFactory.make(
                asset: asset,
                quantity: quantity,
                currentPrice: currentPrice,
                fifo: fifoResult
            )
        }
    }

    // MARK: - Cross-Margin Holdings

    private func computeCrossMarginHoldings() async throws -> [Holding] {
        let allTrades = try fetchTrades(mode: .crossMargin)
        guard !allTrades.isEmpty else { return [] }

        let descriptor = FetchDescriptor<CrossMarginBalance>()
        let crossBalances: [CrossMarginBalance] = (try? modelContext.fetch(descriptor)) ?? []
        guard !crossBalances.isEmpty else { return [] }

        let tradesByAsset = Dictionary(grouping: allTrades.map(Self.toFIFOTrade)) { $0.asset }

        let interestByAsset = Dictionary(
            crossBalances.map { ($0.asset, $0.interest) },
            uniquingKeysWith: { first, _ in first }
        )

        var holdings: [Holding] = []
        for (asset, assetTrades) in tradesByAsset {
            let fifoResult = fifoCalculator.calculate(assetTrades)
            let interest = interestByAsset[asset] ?? 0
            let marginResult = fifoCalculator.calculateMargin(assetTrades, [asset: interest])

            let balance = crossBalances.first { $0.asset == asset }
            let quantity = balance?.netAsset ?? marginResult.totalRemainingQuantity
            let borrowedQuantity = balance?.borrowed
            let marginAdjustedPnL: Double? = marginResult.marginAdjustedRealizedPnL > 0 || marginResult.totalBorrowingFees > 0
                ? marginResult.marginAdjustedRealizedPnL
                : nil

            if quantity > 0 || marginResult.isMarginPosition {
                holdings.append(HoldingFactory.make(
                    asset: asset,
                    quantity: quantity,
                    currentPrice: 0,
                    fifo: fifoResult,
                    borrowedQuantity: borrowedQuantity,
                    marginAdjustedPnL: marginAdjustedPnL,
                    liquidationPrice: nil
                ))
            }
        }

        return sortHoldings(holdings)
    }

    // MARK: - Isolated-Margin Holdings

    private func computeIsolatedMarginHoldings() -> [Holding] {
        let allTrades = try? fetchTrades(mode: .isolatedMargin)
        guard let trades = allTrades, !trades.isEmpty else { return [] }

        let descriptor = FetchDescriptor<MarginBalance>()
        let marginBalances: [MarginBalance] = (try? modelContext.fetch(descriptor)) ?? []

        let tradesByAsset = Dictionary(grouping: trades.map(Self.toFIFOTrade)) { $0.asset }
        let interestByAsset = Dictionary(marginBalances.map { ($0.asset, $0.interest) }, uniquingKeysWith: { first, _ in first })

        var holdings: [Holding] = []
        for (asset, assetTrades) in tradesByAsset {
            let fifoResult = fifoCalculator.calculate(assetTrades)
            let borrowingFees = interestByAsset[asset].map { [asset: $0] } ?? [:]
            let marginResult = fifoCalculator.calculateMargin(assetTrades, borrowingFees)

            let marginBalance = marginBalances.first { $0.asset == asset }
            let quantity = marginBalance?.netAsset ?? marginResult.totalRemainingQuantity
            let borrowedQuantity = marginBalance.map { $0.borrowed }
            let marginAdjustedPnL: Double? = marginResult.marginAdjustedRealizedPnL > 0 || marginResult.totalBorrowingFees > 0
                ? marginResult.marginAdjustedRealizedPnL
                : nil

            if quantity > 0 || marginResult.isMarginPosition {
                holdings.append(HoldingFactory.make(
                    asset: asset,
                    quantity: quantity,
                    currentPrice: 0,
                    fifo: fifoResult,
                    borrowedQuantity: borrowedQuantity,
                    marginAdjustedPnL: marginAdjustedPnL
                ))
            }
        }

        return sortHoldings(holdings)
    }

    // MARK: - Data Access Helpers

    private func fetchSyncMap() -> [String: Int64] {
        let descriptor = FetchDescriptor<SyncMetadata>()
        guard let metadata = try? modelContext.fetch(descriptor) else { return [:] }
        return Dictionary(metadata.map { ($0.symbol, $0.lastTradeId) }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchTrades(mode: TradingMode) throws -> [Trade] {
        let predicate = #Predicate<Trade> { $0.tradingMode == mode.rawValue }
        var descriptor = FetchDescriptor<Trade>(predicate: predicate, sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchPersistedSpotBalances() -> [String: Double] {
        let descriptor = FetchDescriptor<AccountBalance>()
        guard let balances = try? modelContext.fetch(descriptor) else { return [:] }
        return Dictionary(
            balances.map { ($0.asset, $0.quantity) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func fetchAllTrades() throws -> [Trade] {
        let descriptor = FetchDescriptor<Trade>(sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    private func sortHoldings(_ holdings: [Holding]) -> [Holding] {
        holdings.sorted { $0.totalInvestedUSDT > $1.totalInvestedUSDT }
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

    private func persistTrades(_ mappedTrades: [MappedTrade], mode: TradingMode) throws {
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
                tradingMode: mode
            )
            modelContext.insert(trade)
        }
        try modelContext.save()
    }

    private func persistCrossMarginBalances() async throws {
        let balances = try await marginBalanceService.fetchCrossMarginBalances()

        // Delete existing cross-margin balance rows
        try modelContext.delete(model: CrossMarginBalance.self)

        for balance in balances {
            modelContext.insert(balance)
        }
        try modelContext.save()
    }

    // MARK: - Summary for Tab

    func summary(for tab: PortfolioTab) -> PortfolioSummary {
        switch tab {
        case .overview:
            return state.summary
        case .spot:
            return PortfolioSummary(from: state.summary.spot)
        case .crossMargin:
            return PortfolioSummary(from: state.summary.crossMargin)
        case .isolatedMargin:
            return PortfolioSummary(from: state.summary.isolatedMargin)
        }
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
