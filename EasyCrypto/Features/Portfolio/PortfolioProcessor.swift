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

    private let marginTradeImportService: MarginTradeImportService
    private let marginBalanceService: MarginBalanceService

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
        self.modelContext = ModelContext(modelContainer)
        self.marginTradeImportService = marginTradeImportService
        self.marginBalanceService = marginBalanceService
    }

    // MARK: - Intent Handler

    func handle(_ intent: PortfolioIntent) async {
        switch intent {
        case .refresh:
            await refresh()
        case .sortHoldings(let criteria):
            state.sortCriteria = criteria
            state.holdings = Self.sortHoldings(state.holdings, by: criteria)
        }
    }

    // MARK: - Mode-Aware Refresh

    private func refresh() async {
        state.isLoading = true
        state.error = nil

        do {
            switch state.selectedTradingMode {
            case .spot:
                try await refreshSpot()
            case .crossMargin, .isolatedMargin:
                try await refreshMargin(mode: state.selectedTradingMode)
            }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Spot Refresh

    private func refreshSpot() async throws {
        let syncMap = fetchSyncMap()
        let importResult = try await tradeImportService.sync(syncMap)

        persistSyncUpdates(importResult.syncUpdates)
        try persistTrades(importResult.mappedTrades, mode: .spot)

        let portfolioData = try await computeSpotPortfolioData()
        state.holdings = Self.sortHoldings(portfolioData.holdings, by: state.sortCriteria)
        state.summary = PortfolioSummary(
            from: state.holdings,
            totalRealizedPnL: portfolioData.totalRealizedPnL
        )
        state.lastRefreshDate = Date()
    }

    // MARK: - Margin Refresh

    private func refreshMargin(mode: TradingMode) async throws {
        // 1. Sync trades for this mode
        let syncMap = fetchSyncMap()
        let importResult = try await marginTradeImportService.sync(mode, syncMap)
        persistSyncUpdates(importResult.syncUpdates)
        try persistTrades(importResult.mappedTrades, mode: mode)

        // 2. Load quantities and interest based on mode
        let (balances, perAssetInterest) = try await fetchMarginQuantities(mode: mode)
        try persistBalances(balances, mode: mode)

        // 3. Fetch mode-filtered trades and compute holdings with margin-adjusted P&L
        let modeTrades = try fetchPersistedTrades(matching: mode)
        let balanceDict = Dictionary(
            balances.map { ($0.asset, $0.quantity) },
            uniquingKeysWith: { first, _ in first }
        )

        let portfolioData = try await computeMarginPortfolioData(
            trades: modeTrades,
            balances: balanceDict,
            perAssetInterest: perAssetInterest
        )
        state.holdings = Self.sortHoldings(portfolioData.holdings, by: state.sortCriteria)
        state.summary = PortfolioSummary(
            from: state.holdings,
            totalRealizedPnL: portfolioData.totalRealizedPnL
        )
        state.lastRefreshDate = Date()
    }

    // MARK: - Quantity Loading

    private func fetchMarginQuantities(mode: TradingMode) async throws -> ([AccountBalance], [String: Double]) {
        switch mode {
        case .crossMargin:
            return try await fetchCrossMarginQuantities()
        case .isolatedMargin:
            return try await fetchIsolatedMarginQuantities()
        case .spot:
            return ([], [:])
        }
    }

    private func fetchCrossMarginQuantities() async throws -> ([AccountBalance], [String: Double]) {
        guard let accountData = try await marginBalanceService.fetchCrossMarginAccount() else {
            return ([], [:])
        }

        let trades = try fetchPersistedTrades(matching: .crossMargin)
        let tradesByAsset = Dictionary(grouping: trades) { $0.asset }
        var quantities: [String: Double] = [:]
        for (asset, assetTrades) in tradesByAsset {
            let result = fifoCalculator.calculate(assetTrades.map(Self.toFIFOTrade))
            if result.totalRemainingQuantity > 0.001 {
                quantities[asset] = result.totalRemainingQuantity
            }
        }

        let balances = quantities.map { AccountBalance(asset: $0.key, quantity: $0.value, tradingMode: .crossMargin) }
        return (balances, accountData.perAssetInterest)
    }

    private func fetchIsolatedMarginQuantities() async throws -> ([AccountBalance], [String: Double]) {
        let isolatedBalances = try await fetchAllIsolatedMarginBalances()

        let balances: [AccountBalance] = isolatedBalances.compactMap { balance in
            guard balance.netAsset > 0.001 else { return nil }
            return AccountBalance(
                asset: balance.asset,
                quantity: balance.netAsset,
                tradingMode: .isolatedMargin
            )
        }

        let interest: [String: Double] = Dictionary(
            uniqueKeysWithValues: isolatedBalances.compactMap { balance in
                guard balance.netAsset > 0.001 else { return nil }
                let assetKey = balance.symbol.replacingOccurrences(of: "USDT", with: "")
                return (assetKey, balance.interest)
            }
        )

        return (balances, interest)
    }

    // MARK: - Portfolio Data Computation

    private struct PortfolioData {
        let holdings: [Holding]
        let totalRealizedPnL: Double
    }

    private func computeSpotPortfolioData() async throws -> PortfolioData {
        let allTrades = try fetchAllTrades()
        let balances = try await balanceService.fetchBalances()
        let accountBalances = balances.map { AccountBalance(asset: $0.key, quantity: $0.value, tradingMode: .spot) }
        try persistBalances(accountBalances, mode: .spot)

        return try await computeHoldings(
            trades: allTrades.map(Self.toFIFOTrade),
            balances: balances,
            useMarginFIFO: false,
            perAssetInterest: [:]
        )
    }

    private func computeMarginPortfolioData(
        trades: [Trade],
        balances: [String: Double],
        perAssetInterest: [String: Double]
    ) async throws -> PortfolioData {
        return try await computeHoldings(
            trades: trades.map(Self.toFIFOTrade),
            balances: balances,
            useMarginFIFO: true,
            perAssetInterest: perAssetInterest
        )
    }

    private func computeHoldings(
        trades: [FIFOTrade],
        balances: [String: Double],
        useMarginFIFO: Bool,
        perAssetInterest: [String: Double]
    ) async throws -> PortfolioData {
        let tradesByAsset = Dictionary(grouping: trades) { $0.asset }

        var fifoByAsset: [String: FIFOResult] = [:]
        var marginAdjustedPnLByAsset: [String: Double] = [:]
        var totalRealizedPnL: Double = 0

        for (asset, assetTrades) in tradesByAsset {
            if useMarginFIFO, let interest = perAssetInterest[asset] {
                let marginResult = fifoCalculator.calculateMargin(assetTrades, [asset: interest])
                fifoByAsset[asset] = marginResult.fifoResult
                marginAdjustedPnLByAsset[asset] = marginResult.marginAdjustedRealizedPnL
                totalRealizedPnL += marginResult.marginAdjustedRealizedPnL
            } else {
                fifoByAsset[asset] = fifoCalculator.calculate(assetTrades)
                totalRealizedPnL += fifoByAsset[asset]!.realizedPnL
            }
        }

        // Fetch prices for non-USDT assets with meaningful balances
        let dustThreshold = 0.001
        let priceAssets = balances.keys
            .filter { $0 != "USDT" && balances[$0] ?? 0 >= dustThreshold }
        let priceSymbols = priceAssets.map { "\($0)USDT" }
        let prices = try await priceService.fetchPrices(priceSymbols)

        var holdings: [Holding] = []
        for (asset, quantity) in balances where quantity >= dustThreshold {
            let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
            let fifoResult = fifoByAsset[asset] ?? .empty
            let marginPnL = useMarginFIFO ? marginAdjustedPnLByAsset[asset] : nil

            holdings.append(HoldingFactory.make(
                asset: asset,
                quantity: quantity,
                currentPrice: currentPrice,
                fifo: fifoResult,
                marginAdjustedPnL: marginPnL
            ))
        }

        return PortfolioData(holdings: holdings, totalRealizedPnL: totalRealizedPnL)
    }

    // MARK: - Isolated Margin Balance Fetch

    private func fetchAllIsolatedMarginBalances() async throws -> [IsolatedMarginBalance] {
        let persisted = try fetchPersistedMarginBalances()
        let knownSymbols = Set(persisted.map { $0.symbol })

        var results = persisted

        for symbol in knownSymbols {
            guard let liveBalances = try await marginBalanceService.fetchIsolatedMarginBalances(symbol) else {
                continue
            }

            for balance in liveBalances {
                let mb = MarginBalance(
                    symbol: balance.symbol,
                    isolatedMarginKey: "\(balance.symbol):\(balance.asset)",
                    asset: balance.asset,
                    borrowed: balance.borrowed,
                    free: balance.free,
                    locked: balance.locked,
                    interest: balance.interest
                )
                modelContext.insert(mb)
            }

            results.append(contentsOf: liveBalances)
        }

        try modelContext.save()
        return results
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

    private func fetchPersistedTrades(matching mode: TradingMode) throws -> [Trade] {
        let predicate = #Predicate<Trade> { $0.tradingMode == mode.rawValue }
        let descriptor = FetchDescriptor<Trade>(predicate: predicate, sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchPersistedBalances(matching mode: TradingMode) throws -> [AccountBalance] {
        let predicate = #Predicate<AccountBalance> { $0.tradingMode == mode.rawValue }
        let descriptor = FetchDescriptor<AccountBalance>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    private func fetchPersistedMarginBalances() throws -> [IsolatedMarginBalance] {
        let descriptor = FetchDescriptor<MarginBalance>()
        guard let balances = try? modelContext.fetch(descriptor) else { return [] }
        return balances.map { balance in
            IsolatedMarginBalance(
                symbol: balance.symbol,
                asset: balance.asset,
                borrowed: balance.borrowed,
                free: balance.free,
                locked: balance.locked,
                interest: balance.interest,
                netAsset: balance.netAsset
            )
        }
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

    private func persistTrades(_ mappedTrades: [MappedTrade], mode: TradingMode = .spot) throws {
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

    private func persistBalances(_ balances: [AccountBalance], mode: TradingMode) throws {
        let predicate = #Predicate<AccountBalance> { $0.tradingMode == mode.rawValue }
        try modelContext.delete(model: AccountBalance.self, where: predicate)

        for balance in balances {
            modelContext.insert(balance)
        }
        try modelContext.save()
    }

    // MARK: - Sorting

    private static func sortHoldings(_ holdings: [Holding], by criteria: SortCriteria) -> [Holding] {
        switch criteria {
        case .value:
            return holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        case .name:
            return holdings.sorted { $0.asset < $1.asset }
        case .pnl:
            return holdings.sorted { $0.unrealizedPnL > $1.unrealizedPnL }
        case .pnlPercent:
            return holdings.sorted { $0.unrealizedPnLPercent > $1.unrealizedPnLPercent }
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
