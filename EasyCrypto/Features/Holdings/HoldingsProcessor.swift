//
//  HoldingsProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class HoldingsProcessor: Processor {
    var state = HoldingsState()

    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator
    private let modelContext: ModelContext

    private let balanceService: BalanceService
    private let marginTradeImportService: MarginTradeImportService
    private let marginBalanceService: MarginBalanceService

    init(
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer,
        balanceService: BalanceService = .noop,
        marginTradeImportService: MarginTradeImportService = .noop,
        marginBalanceService: MarginBalanceService = .noop
    ) {
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.modelContext = ModelContext(modelContainer)
        self.balanceService = balanceService
        self.marginTradeImportService = marginTradeImportService
        self.marginBalanceService = marginBalanceService
    }

    func handle(_ intent: HoldingsIntent) async {
        switch intent {
        case .loadHoldings:
            await loadHoldings(syncFromExchange: true)
        case .loadPersisted:
            await loadHoldings(syncFromExchange: false)
        case .filterByMode(let mode):
            await filterByMode(mode)
        }
    }

    private func loadHoldings(syncFromExchange: Bool) async {
        state.isLoading = true
        state.error = nil

        do {
            let holdings: [Holding]
            switch state.selectedTradingMode {
            case .spot:
                holdings = try await loadSpotHoldings(usePersistedBalances: !syncFromExchange).holdings
            case .crossMargin:
                let data = try await loadMarginHoldings(mode: .crossMargin, syncFromExchange: syncFromExchange)
                holdings = data.holdings
            case .isolatedMargin:
                let data = try await loadMarginHoldings(mode: .isolatedMargin, syncFromExchange: syncFromExchange)
                holdings = data.holdings
            }
            state.holdings = holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Trading Mode Filter

    private func filterByMode(_ mode: TradingMode) async {
        state.selectedTradingMode = mode
        state.holdings = []
        state.error = nil
        await loadHoldings(syncFromExchange: false)
    }

    // MARK: - Aggregated Holdings (Spot + Cross Margin + Isolated Margin)

    private func loadAggregatedHoldings(syncFromExchange: Bool) async throws -> PortfolioData {
        let spotHoldings = try await loadSpotHoldings(usePersistedBalances: !syncFromExchange)
        let crossHoldings = try await loadMarginHoldings(mode: .crossMargin, syncFromExchange: syncFromExchange)
        let isolatedHoldings = try await loadMarginHoldings(mode: .isolatedMargin, syncFromExchange: syncFromExchange)

        let allHoldings = spotHoldings.holdings + crossHoldings.holdings + isolatedHoldings.holdings
        return PortfolioData(holdings: allHoldings)
    }

    // MARK: - Spot Holdings

    private func loadSpotHoldings(usePersistedBalances: Bool = false) async throws -> PortfolioData {
        let trades = try fetchTrades(matching: .spot)
        let fifoByAsset = computeFIFO(trades)

        let quantities = try await loadSpotQuantities(usePersisted: usePersistedBalances)

        let prices = try await priceService.fetchPrices(PriceCatalog.usdtSymbols(from: Array(quantities.keys), exclude: "USDT"))

        return PortfolioData(
            holdings: buildHoldings(
                quantities: quantities,
                prices: prices,
                fifoByAsset: fifoByAsset,
                marginAdjustedPnLByAsset: [:],
                mode: .spot
            )
        )
    }

    private func loadPersistedSpotBalances() throws -> [String: Double] {
        let descriptor = FetchDescriptor<AccountBalance>()
        let balances = try modelContext.fetch(descriptor)   
        return Dictionary(
            balances.map { ($0.asset, $0.quantity) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Margin Holdings

    private func loadMarginHoldings(mode: TradingMode, syncFromExchange: Bool) async throws -> PortfolioData {

        if syncFromExchange {
            // Sync fresh trades and balances from the exchange before loading.
            let syncMap = fetchSyncMap(mode: mode)
            let importResult = try await marginTradeImportService.sync(mode, syncMap)
            persistSyncUpdates(importResult.syncUpdates, mode: mode)
            try persistTrades(importResult.mappedTrades, mode: mode)
        }

        // Isolated-margin quantities come exclusively from persisted balances, so they
        // also have to be bootstrapped when the mode is shown without a full sync.
        if mode == .isolatedMargin {
            let hasPersistedBalances = try !fetchPersistedMarginBalances().isEmpty
            if syncFromExchange || !hasPersistedBalances {
                let isolatedBalances = try await fetchAllIsolatedMarginBalancesLive()
                try persistIsolatedMarginBalances(isolatedBalances)
            }
        }

        let trades = try fetchTrades(matching: mode)
        let tradesByAsset = Dictionary(grouping: trades) { $0.asset }

        var fifoByAsset: [String: FIFOResult] = [:]
        var marginAdjustedPnLByAsset: [String: Double] = [:]

        for (asset, assetTrades) in tradesByAsset {
            let assetFifoTrades = assetTrades.map(Self.toFIFOTrade)
            let result = fifoCalculator.calculate(assetFifoTrades)
            fifoByAsset[asset] = result
        }

        let (quantities, perAssetInterest) = try await loadMarginQuantities(mode: mode)

        for (asset, assetTrades) in tradesByAsset {
            let assetFifoTrades = assetTrades.map(Self.toFIFOTrade)
            let interest = perAssetInterest[asset] ?? 0
            let marginResult = fifoCalculator.calculateMargin(assetFifoTrades, [asset: interest])
            marginAdjustedPnLByAsset[asset] = marginResult.marginAdjustedRealizedPnL
        }

        let prices = try await priceService.fetchPrices(PriceCatalog.usdtSymbols(from: Array(quantities.keys), exclude: "USDT"))

        return PortfolioData(
            holdings: buildHoldings(
                quantities: quantities,
                prices: prices,
                fifoByAsset: fifoByAsset,
                marginAdjustedPnLByAsset: marginAdjustedPnLByAsset,
                mode: mode
            )
        )
    }

    // MARK: - Quantity Loading

    /// Spot quantities live in `AccountBalance`, which only this path writes — so an
    /// empty table has to fall through to the exchange even on a persisted-only load.
    /// A live fetch that returns nothing never clobbers what is already stored.
    private func loadSpotQuantities(usePersisted: Bool) async throws -> [String: Double] {
        let persisted = try loadPersistedSpotBalances()
        if usePersisted && !persisted.isEmpty { return persisted }

        let live = try await balanceService.fetchBalances()
        guard !live.isEmpty else { return persisted }

        try persistSpotBalances(live)
        return live
    }

    private func persistSpotBalances(_ balances: [String: Double]) throws {
        let spotMode = TradingMode.spot.rawValue
        try modelContext.delete(
            model: AccountBalance.self,
            where: #Predicate { $0.tradingMode == spotMode }
        )
        for (asset, quantity) in balances {
            modelContext.insert(AccountBalance(asset: asset, quantity: quantity))
        }
        try modelContext.save()
    }

    private func loadMarginQuantities(mode: TradingMode) async throws -> ([String: Double], [String: Double]) {

        if mode == .isolatedMargin {
            // Load from persisted MarginBalance model for isolated margin. The same asset
            // can appear in several pairs (USDT especially), so sum rather than pick one.
            let marginBalances = try fetchPersistedMarginBalances()
            let quantities = Dictionary(
                marginBalances.map { ($0.asset, $0.netAsset) },
                uniquingKeysWith: +
            )
            let interest = Dictionary(
                marginBalances.map { ($0.asset, $0.interest) },
                uniquingKeysWith: +
            )
            return (quantities, interest)
        } else {
            // Cross-margin: no persistent per-asset quantity model.
            // Use FIFO remaining quantity as a proxy; real cross-margin balances
            // come from AccountBalance rows populated by PortfolioProcessor refresh.
            let allTrades = try fetchTrades(matching: .crossMargin)
            let tradesByAsset = Dictionary(grouping: allTrades) { $0.asset }
            var quantities: [String: Double] = [:]
            var interest: [String: Double] = [:]
            for (asset, assetTrades) in tradesByAsset {
                let result = fifoCalculator.calculate(assetTrades.map(Self.toFIFOTrade))
                guard result.totalRemainingQuantity > 0 else { continue }
                quantities[asset] = result.totalRemainingQuantity
            }
            return (quantities, interest)
        }
    }

    // MARK: - Building Holdings

    private func buildHoldings(
        quantities: [String: Double],
        prices: [String: Double],
        fifoByAsset: [String: FIFOResult],
        marginAdjustedPnLByAsset: [String: Double],
        mode: TradingMode = .spot
    ) -> [Holding] {
        var holdings: [Holding] = []
        for (asset, quantity) in quantities where quantity > 0.001 {
            let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
            let fifo = fifoByAsset[asset] ?? .empty
            let marginPnL = marginAdjustedPnLByAsset[asset]
            holdings.append(HoldingFactory.make(
                asset: asset,
                quantity: quantity,
                currentPrice: currentPrice,
                fifo: fifo,
                tradingMode: mode,
                marginAdjustedPnL: marginPnL
            ))
        }
        return holdings
    }

    // MARK: - Data Access Helpers

    private func fetchTrades(matching mode: TradingMode) throws -> [Trade] {
        let predicate = #Predicate<Trade> { $0.tradingMode == mode.rawValue }
        let descriptor = FetchDescriptor<Trade>(predicate: predicate, sortBy: [SortDescriptor(\.binanceTradeId)])
        return try modelContext.fetch(descriptor)
    }

    private func computeFIFO(_ trades: [Trade]) -> [String: FIFOResult] {
        let tradesByAsset = Dictionary(grouping: trades) { $0.asset }
        return Dictionary(
            uniqueKeysWithValues: tradesByAsset.compactMap { asset, assetTrades in
                let result = fifoCalculator.calculate(assetTrades.map(Self.toFIFOTrade))
                return (asset, result)
            }
        )
    }

    private func fetchPersistedMarginBalances() throws -> [MarginBalance] {
        let descriptor = FetchDescriptor<MarginBalance>()
        guard let balances = try? modelContext.fetch(descriptor) else { return [] }
        return balances
    }

    // MARK: - Sync & Persistence Helpers

    private func fetchSyncMap(mode: TradingMode) -> [String: Int64] {
        let rawMode = mode.rawValue
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.tradingMode == rawMode }
        )
        guard let metadata = try? modelContext.fetch(descriptor) else { return [:] }
        return Dictionary(metadata.map { ($0.symbol, $0.lastTradeId) }, uniquingKeysWith: { first, _ in first })
    }

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

    private func persistIsolatedMarginBalances(_ balances: [IsolatedMarginBalance]) throws {
        // Delete existing persisted MarginBalance rows
        try modelContext.delete(model: MarginBalance.self)
        for balance in balances {
            modelContext.insert(MarginBalance(
                symbol: balance.symbol,
                // Each pair yields a base *and* a quote asset row, so the uniqueness key
                // must include the asset — keying on the pair symbol alone made the two
                // rows collide and upsert into one.
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

    private func fetchAllIsolatedMarginBalancesLive() async throws -> [IsolatedMarginBalance] {
        // Queries the isolated account without a symbol filter: the user's open pairs
        // are otherwise undiscoverable, and seeding from persisted rows could never
        // bootstrap on a fresh install.
        try await marginBalanceService.fetchAllIsolatedMarginBalances()
    }

    // MARK: - Portfolio Data

    private struct PortfolioData {
        let holdings: [Holding]
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

