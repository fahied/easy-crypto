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

    private let marginTradeImportService: MarginTradeImportService
    private let marginBalanceService: MarginBalanceService

    init(
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer,
        marginTradeImportService: MarginTradeImportService = .noop,
        marginBalanceService: MarginBalanceService = .noop
    ) {
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.modelContext = ModelContext(modelContainer)
        self.marginTradeImportService = marginTradeImportService
        self.marginBalanceService = marginBalanceService
    }

    func handle(_ intent: HoldingsIntent) async {
        switch intent {
        case .loadHoldings:
            await loadHoldings()
        case .setTradingMode(let mode):
            state.selectedTradingMode = mode
        }
    }

    private func loadHoldings() async {
        state.isLoading = true
        state.error = nil

        do {
            let portfolioData: PortfolioData

            switch state.selectedTradingMode {
            case .spot:
                portfolioData = try await loadSpotHoldings()
            case .crossMargin, .isolatedMargin:
                portfolioData = try await loadMarginHoldings()
            }

            state.holdings = portfolioData.holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    // MARK: - Spot Holdings

    private func loadSpotHoldings() async throws -> PortfolioData {
        let trades = try fetchTrades(matching: .spot)
        let fifoByAsset = computeFIFO(trades)
        let quantities = try loadSpotQuantities()
        let prices = try await priceService.fetchPrices(quantityKeys(quantities, exclude: "USDT"))

        return PortfolioData(
            holdings: buildHoldings(
                quantities: quantities,
                prices: prices,
                fifoByAsset: fifoByAsset,
                marginAdjustedPnLByAsset: [:]
            )
        )
    }

    // MARK: - Margin Holdings

    private func loadMarginHoldings() async throws -> PortfolioData {
        let trades = try fetchTrades(matching: state.selectedTradingMode)

        let tradesByAsset = Dictionary(grouping: trades) { $0.asset }

        var fifoByAsset: [String: FIFOResult] = [:]
        var marginAdjustedPnLByAsset: [String: Double] = [:]

        for (asset, assetTrades) in tradesByAsset {
            let assetFifoTrades = assetTrades.map(Self.toFIFOTrade)
            let result = fifoCalculator.calculate(assetFifoTrades)
            fifoByAsset[asset] = result
        }

        let (quantities, perAssetInterest) = try await loadMarginQuantities()

        for (asset, assetTrades) in tradesByAsset {
            let assetFifoTrades = assetTrades.map(Self.toFIFOTrade)
            let interest = perAssetInterest[asset] ?? 0
            let marginResult = fifoCalculator.calculateMargin(assetFifoTrades, [asset: interest])
            marginAdjustedPnLByAsset[asset] = marginResult.marginAdjustedRealizedPnL
        }

        let prices = try await priceService.fetchPrices(quantityKeys(quantities, exclude: "USDT"))

        return PortfolioData(
            holdings: buildHoldings(
                quantities: quantities,
                prices: prices,
                fifoByAsset: fifoByAsset,
                marginAdjustedPnLByAsset: marginAdjustedPnLByAsset
            )
        )
    }

    // MARK: - Quantity Loading

    private func loadSpotQuantities() throws -> [String: Double] {
        let persisted = try modelContext.fetch(FetchDescriptor<AccountBalance>())
        let quantities = Dictionary(
            persisted.map { ($0.asset, $0.quantity) },
            uniquingKeysWith: { first, _ in first }
        )
        return quantities
    }

    private func loadMarginQuantities() async throws -> ([String: Double], [String: Double]) {
        let mode = state.selectedTradingMode

        if mode == .isolatedMargin {
            // Load from persisted MarginBalance model for isolated margin
            let marginBalances = try fetchPersistedMarginBalances()
            let quantities = Dictionary(
                marginBalances.map { ($0.asset, $0.netAsset) },
                uniquingKeysWith: { first, _ in first }
            )
            let interest = Dictionary(
                marginBalances.map { ($0.asset, $0.interest) },
                uniquingKeysWith: { first, _ in first }
            )
            return (quantities, interest)
        } else {
            // Cross-margin: no persistent per-asset quantity model.
            // Use FIFO remaining quantity as a proxy.
            let trades = try fetchTrades(matching: .crossMargin)
            let fifoTrades = trades.map(Self.toFIFOTrade)
            let fifoResult = fifoCalculator.calculate(fifoTrades)
            // Fall back to empty — cross-margin quantities come from live API during refresh
            // HoldingsProcessor reads persisted data, so cross-margin may show empty until
            // the next portfolio refresh populates AccountBalance rows.
            let allTrades = try fetchTrades(matching: .crossMargin)
            let tradesByAsset = Dictionary(grouping: allTrades) { $0.asset }
            var quantities: [String: Double] = [:]
            var interest: [String: Double] = [:]
            for (asset, assetTrades) in tradesByAsset {
                let result = fifoCalculator.calculate(assetTrades.map(Self.toFIFOTrade))
                quantities[asset] = result.totalRemainingQuantity > 0 ? result.totalRemainingQuantity : nil
            }
            return (quantities, interest)
        }
    }

    // MARK: - Building Holdings

    private func buildHoldings(
        quantities: [String: Double],
        prices: [String: Double],
        fifoByAsset: [String: FIFOResult],
        marginAdjustedPnLByAsset: [String: Double]
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

    private func quantityKeys(_ dict: [String: Double], exclude: String) -> [String] {
        dict.keys.filter { $0 != exclude }.map { "\($0)USDT" }
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

