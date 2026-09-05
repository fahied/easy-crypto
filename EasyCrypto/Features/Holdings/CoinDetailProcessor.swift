//
//  CoinDetailProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class CoinDetailProcessor: Processor {
    var state = CoinDetailState()

    private let apiClient: BinanceAPIClient
    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator
    private let modelContext: ModelContext

    init(
        apiClient: BinanceAPIClient,
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer
    ) {
        self.apiClient = apiClient
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.modelContext = ModelContext(modelContainer)
    }

    func handle(_ intent: CoinDetailIntent) async {
        switch intent {
        case .loadDetail(let asset, let tradingMode):
            await loadDetail(asset: asset, tradingMode: tradingMode)
        case .changeChartInterval(let interval):
            await changeInterval(interval)
        }
    }

    private func loadDetail(asset: String, tradingMode: TradingMode) async {
        state.asset = asset
        state.isLoading = true
        state.error = nil

        do {
            let symbol = "\(asset)USDT"

            // Fetch trades for this asset and trading mode from SwiftData.
            // Filtering by mode matches HoldingsProcessor.fetchTrades(matching:) so
            // the detail view shows the same trades (and avg price) as the list.
            let predicate = #Predicate<Trade> { $0.asset == asset && $0.tradingMode == tradingMode.rawValue }
            let descriptor = FetchDescriptor<Trade>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let trades = try modelContext.fetch(descriptor)
            state.trades = trades

            // Compute holding via FIFO
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

            let result = fifoCalculator.calculate(fifoTrades)
            let prices = try await priceService.fetchPrices([symbol])
            let currentPrice = prices[symbol] ?? 0
            let invested = result.totalInvestedUSDT
            let fifoQuantity = result.totalRemainingQuantity
            let currentValue = fifoQuantity * currentPrice
            let unrealizedPnL = invested > 0 ? currentValue - invested : 0
            let unrealizedPnLPercent = invested > 0
                ? (unrealizedPnL / invested) * 100 : 0

            state.holding = Holding(
                asset: asset,
                totalQuantity: fifoQuantity,
                weightedAvgBuyPrice: 0,
                totalInvestedUSDT: invested,
                currentPrice: currentPrice,
                currentValueUSDT: currentValue,
                unrealizedPnL: unrealizedPnL,
                unrealizedPnLPercent: unrealizedPnLPercent,
                realizedPnL: result.realizedPnL,
                tradingMode: tradingMode
            )

            // Fetch klines for chart
            let klines = try await apiClient.fetchKlines(symbol, state.chartInterval.rawValue, 100)
            state.klines = klines
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    private func changeInterval(_ interval: ChartInterval) async {
        state.chartInterval = interval
        guard !state.asset.isEmpty else { return }

        do {
            let symbol = "\(state.asset)USDT"
            let klines = try await apiClient.fetchKlines(symbol, interval.rawValue, 100)
            state.klines = klines
        } catch {
            state.error = error.localizedDescription
        }
    }
}
