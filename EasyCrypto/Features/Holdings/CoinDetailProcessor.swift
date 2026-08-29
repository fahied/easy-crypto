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
        case .loadDetail(let asset):
            await loadDetail(asset: asset)
        case .changeChartInterval(let interval):
            await changeInterval(interval)
        }
    }

    private func loadDetail(asset: String) async {
        state.asset = asset
        state.isLoading = true
        state.error = nil

        do {
            let symbol = "\(asset)USDT"

            // Fetch trades for this asset from SwiftData
            let predicate = #Predicate<Trade> { $0.asset == asset }
            var descriptor = FetchDescriptor<Trade>(
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
            let avgBuyPrice = result.simpleAvgBuyPrice
            let currentValue = result.totalRemainingQuantity * currentPrice
            let unrealizedPnL = avgBuyPrice > 0 ? (currentPrice - avgBuyPrice) * result.totalRemainingQuantity : 0
            let unrealizedPnLPercent = avgBuyPrice > 0 ? (unrealizedPnL / (avgBuyPrice * result.totalRemainingQuantity)) * 100 : 0

            state.holding = Holding(
                asset: asset,
                totalQuantity: result.totalRemainingQuantity,
                weightedAvgBuyPrice: avgBuyPrice,
                totalInvestedUSDT: avgBuyPrice * result.totalRemainingQuantity,
                currentPrice: currentPrice,
                currentValueUSDT: currentValue,
                unrealizedPnL: unrealizedPnL,
                unrealizedPnLPercent: unrealizedPnLPercent,
                realizedPnL: result.realizedPnL
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
