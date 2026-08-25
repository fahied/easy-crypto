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
        case .showInvestedAssets:
            await handleShowInvestedAssets()
        }
    }

    // MARK: - Load from Persisted Data

    /// Builds the portfolio summary from SwiftData trades (not balances) — balances
    /// come from the live API via `marginBalanceService` to avoid stale data.
    /// Used on launch to show cached data immediately.
    private func loadPersistedData() async {
        state.isLoading = true
        state.error = nil

        do {
            state.summary = try await computeSummary()
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
            let spotSyncMap = fetchSyncMap(mode: .spot)
            let spotImport = try await tradeImportService.sync(spotSyncMap)
            persistSyncUpdates(spotImport.syncUpdates, mode: .spot)
            try persistTrades(spotImport.mappedTrades, mode: .spot)

            // Sync margin trades for cross-margin and isolated-margin in parallel
            let crossSyncMap = fetchSyncMap(mode: .crossMargin)
            let isolatedSyncMap = fetchSyncMap(mode: .isolatedMargin)
            async let crossImport = marginTradeImportService.sync(.crossMargin, crossSyncMap)
            async let isolatedImport = marginTradeImportService.sync(.isolatedMargin, isolatedSyncMap)

            let crossResult = try await crossImport
            let isolatedResult = try await isolatedImport

            persistSyncUpdates(crossResult.syncUpdates, mode: .crossMargin)
            try persistTrades(crossResult.mappedTrades, mode: .crossMargin)
            try await persistCrossMarginBalances()

            persistSyncUpdates(isolatedResult.syncUpdates, mode: .isolatedMargin)
            try persistTrades(isolatedResult.mappedTrades, mode: .isolatedMargin)
            try await persistIsolatedMarginBalances()

            state.summary = try await computeSummary()
            state.lastRefreshDate = Date()
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Summary Computation

    private func computeSummary() async throws -> PortfolioSummary {
        let (spotHoldings, crossHoldings, isolatedHoldings) = try await computeAllHoldings()

        let spotRealized = realizedPnL(mode: .spot)
        let crossRealized = realizedPnL(mode: .crossMargin)
        let isolatedRealized = realizedPnL(mode: .isolatedMargin)

        let spotSummary = PortfolioSummary(from: spotHoldings, totalRealizedPnL: spotRealized)
        let crossSummary = PortfolioSummary(from: crossHoldings, totalRealizedPnL: crossRealized)
        let isolatedSummary = PortfolioSummary(from: isolatedHoldings, totalRealizedPnL: isolatedRealized)

        let allHoldings = spotHoldings + crossHoldings + isolatedHoldings

        let totalInvested = allHoldings.reduce(0.0) { $0 + $1.totalInvestedUSDT }
        let totalCurrent = allHoldings.reduce(0.0) { $0 + $1.currentValueUSDT }
        let totalUnrealized = allHoldings.reduce(0.0) { $0 + $1.unrealizedPnL }
        let totalRealized = spotRealized + crossRealized + isolatedRealized
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

    /// Computes all three mode's holdings in parallel. Shared between summary
    /// computation and the invested-assets detail view.
    private func computeAllHoldings() async throws -> (spot: [Holding], cross: [Holding], isolated: [Holding]) {
        async let spot = computeSpotHoldings()
        async let cross = computeCrossMarginHoldings()
        async let isolated = computeIsolatedMarginHoldings()

        let spotResult = try await spot
        let crossResult = try await cross
        let isolatedResult = try await isolated

        return (spotResult, crossResult, isolatedResult)
    }

    // MARK: - Invested Assets Detail

    private func handleShowInvestedAssets() async {
        state.investedAssetsDestination = nil

        do {
            let (spot, cross, isolated) = try await computeAllHoldings()

            let rows: [InvestedAssetRow] = (spot + cross + isolated)
                .filter { $0.totalInvestedUSDT > 0 }
                .map { holding in
                    InvestedAssetRow(
                        asset: holding.asset,
                        tradingMode: holding.tradingMode,
                        amountInvestedUSDT: holding.totalInvestedUSDT,
                        currentValueUSDT: holding.currentValueUSDT
                    )
                }
                .sorted { $0.amountInvestedUSDT > $1.amountInvestedUSDT }

            let totalInvested = rows.reduce(0.0) { $0 + $1.amountInvestedUSDT }
            let totalCurrent = rows.reduce(0.0) { $0 + $1.currentValueUSDT }

            state.investedAssetsDestination = InvestedAssetsDestination(
                assets: rows,
                totalInvested: totalInvested,
                totalCurrentValue: totalCurrent
            )
        } catch {
            state.error = error.localizedDescription
        }
    }

    // MARK: - Spot Holdings

    private func computeSpotHoldings() async throws -> [Holding] {
        let allTrades = (try? fetchTrades(mode: .spot)) ?? []

        let balances = try await balanceService.fetchBalances()
        guard !allTrades.isEmpty || !balances.isEmpty else { return [] }

        let tradesByAsset = Dictionary(grouping: allTrades.map(Self.toFIFOTrade)) { $0.asset }

        var fifoByAsset: [String: FIFOResult] = [:]
        for (asset, assetTrades) in tradesByAsset {
            fifoByAsset[asset] = fifoCalculator.calculate(assetTrades)
        }

        // Include all assets that ever appeared in spot trades, not just active ones
        let tradeAssets = Set(tradesByAsset.keys)
        let balanceAssets = Set(balances.keys)
        let allAssets = tradeAssets.union(balanceAssets)

        let priceSymbols = PriceCatalog.usdtSymbols(from: Array(allAssets))
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

    /// Holdings are keyed by the union of traded assets and account balances — a margin
    /// account's quote-asset float (USDT) has no trades of its own but is real value.
    private func computeCrossMarginHoldings() async throws -> [Holding] {
        let allTrades = (try? fetchTrades(mode: .crossMargin)) ?? []

        let crossBalances = (try? await marginBalanceService.fetchCrossMarginBalances()) ?? []
        guard !allTrades.isEmpty || !crossBalances.isEmpty else { return [] }

        let tradesByAsset = Dictionary(grouping: allTrades.map(Self.toFIFOTrade)) { $0.asset }
        let balanceByAsset = Dictionary(
            crossBalances.map { ($0.asset, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let assets = Set(tradesByAsset.keys).union(balanceByAsset.keys)
        let prices = try await fetchPrices(for: Array(assets))

        var holdings: [Holding] = []
        for asset in assets {
            let assetTrades = tradesByAsset[asset] ?? []
            let balance = balanceByAsset[asset]
            let fifoResult = assetTrades.isEmpty ? .empty : fifoCalculator.calculate(assetTrades)
            let marginResult = fifoCalculator.calculateMargin(assetTrades, [asset: balance?.interest ?? 0])

            let quantity = balance?.netAsset ?? marginResult.totalRemainingQuantity
            let marginAdjustedPnL: Double? = marginResult.marginAdjustedRealizedPnL > 0 || marginResult.totalBorrowingFees > 0
                ? marginResult.marginAdjustedRealizedPnL
                : nil

            if quantity > 0 || marginResult.isMarginPosition {
                holdings.append(HoldingFactory.make(
                    asset: asset,
                    quantity: quantity,
                    currentPrice: price(of: asset, in: prices),
                    fifo: fifoResult,
                    tradingMode: .crossMargin,
                    borrowedQuantity: balance?.borrowed,
                    marginAdjustedPnL: marginAdjustedPnL,
                    liquidationPrice: nil
                ))
            }
        }

        return sortHoldings(holdings)
    }

    // MARK: - Isolated-Margin Holdings

    private func computeIsolatedMarginHoldings() async throws -> [Holding] {
        let trades = (try? fetchTrades(mode: .isolatedMargin)) ?? []

        let isolatedBalances = (try? await marginBalanceService.fetchAllIsolatedMarginBalances()) ?? []
        guard !trades.isEmpty || !isolatedBalances.isEmpty else { return [] }

        let baseBalances = isolatedBalances.filter { $0.role == .base }
        let tradesByAsset = Dictionary(grouping: trades.map(Self.toFIFOTrade)) { $0.asset }
        // An asset appears once per pair it trades in, so sum rather than pick one row.
        let netAssetByAsset = Dictionary(baseBalances.map { ($0.asset, $0.netAsset) }, uniquingKeysWith: +)
        let interestByAsset = Dictionary(baseBalances.map { ($0.asset, $0.interest) }, uniquingKeysWith: +)
        let borrowedByAsset = Dictionary(baseBalances.map { ($0.asset, $0.borrowed) }, uniquingKeysWith: +)

        let assets = Set(tradesByAsset.keys).union(netAssetByAsset.keys)
        let prices = try await fetchPrices(for: Array(assets))

        var holdings: [Holding] = []
        for asset in assets {
            let assetTrades = tradesByAsset[asset] ?? []
            let fifoResult = assetTrades.isEmpty ? .empty : fifoCalculator.calculate(assetTrades)
            let borrowingFees = interestByAsset[asset].map { [asset: $0] } ?? [:]
            let marginResult = fifoCalculator.calculateMargin(assetTrades, borrowingFees)

            let quantity = netAssetByAsset[asset] ?? marginResult.totalRemainingQuantity
            let marginAdjustedPnL: Double? = marginResult.marginAdjustedRealizedPnL > 0 || marginResult.totalBorrowingFees > 0
                ? marginResult.marginAdjustedRealizedPnL
                : nil

            if quantity > 0 || marginResult.isMarginPosition {
                holdings.append(HoldingFactory.make(
                    asset: asset,
                    quantity: quantity,
                    currentPrice: price(of: asset, in: prices),
                    fifo: fifoResult,
                    tradingMode: .isolatedMargin,
                    borrowedQuantity: borrowedByAsset[asset],
                    marginAdjustedPnL: marginAdjustedPnL
                ))
            }
        }

        return sortHoldings(holdings)
    }

    // MARK: - Pricing

    private func fetchPrices(for assets: [String]) async throws -> [String: Double] {
        try await priceService.fetchPrices(PriceCatalog.usdtSymbols(from: assets))
    }

    private func price(of asset: String, in prices: [String: Double]) -> Double {
        asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
    }

    /// Realized P&L across an entire market's trade history.
    private func realizedPnL(mode: TradingMode) -> Double {
        guard let trades = try? fetchTrades(mode: mode) else { return 0 }
        let byAsset = Dictionary(grouping: trades.map(Self.toFIFOTrade)) { $0.asset }
        return byAsset.values.reduce(0.0) { $0 + fifoCalculator.calculate($1).realizedPnL }
    }

    // MARK: - Data Access Helpers

    private func fetchSyncMap(mode: TradingMode) -> [String: Int64] {
        let rawMode = mode.rawValue
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.tradingMode == rawMode }
        )
        guard let metadata = try? modelContext.fetch(descriptor) else { return [:] }
        return Dictionary(metadata.map { ($0.symbol, $0.lastTradeId) }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchTrades(mode: TradingMode) throws -> [Trade] {
        let predicate = #Predicate<Trade> { $0.tradingMode == mode.rawValue }
        var descriptor = FetchDescriptor<Trade>(predicate: predicate, sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    private func sortHoldings(_ holdings: [Holding]) -> [Holding] {
        holdings.sorted { $0.totalInvestedUSDT > $1.totalInvestedUSDT }
    }

    // MARK: - Persistence Helpers

    private func persistSyncUpdates(_ updates: [SyncUpdate], mode: TradingMode) {
        for update in updates {
            let entity = SyncMetadata(
                symbol: update.symbol,
                lastTradeId: update.lastTradeId,
                lastSyncDate: Date(),
                tradingMode: mode
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

    /// Mirrors `persistCrossMarginBalances` for isolated pairs, so the portfolio no
    /// longer depends on the Holdings tab having been opened to have balances at all.
    private func persistIsolatedMarginBalances() async throws {
        let balances = try await marginBalanceService.fetchAllIsolatedMarginBalances()
        guard !balances.isEmpty else { return }

        try modelContext.delete(model: MarginBalance.self)

        for balance in balances {
            modelContext.insert(MarginBalance(
                symbol: balance.symbol,
                isolatedMarginKey: "\(balance.symbol)#\(balance.asset)",
                asset: balance.asset,
                borrowed: balance.borrowed,
                free: balance.free,
                locked: balance.locked,
                interest: balance.interest
            ))
        }
        try modelContext.save()
    }

    // MARK: - Summary for Display

    /// Always returns the full aggregated summary across all trading modes.
    var aggregateSummary: PortfolioSummary { state.summary }

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
