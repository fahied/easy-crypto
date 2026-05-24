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

    init(
        priceService: PriceService,
        fifoCalculator: FIFOCalculator,
        modelContainer: ModelContainer
    ) {
        self.priceService = priceService
        self.fifoCalculator = fifoCalculator
        self.modelContext = ModelContext(modelContainer)
    }

    func handle(_ intent: HoldingsIntent) async {
        switch intent {
        case .loadHoldings:
            await loadHoldings()
        }
    }

    private func loadHoldings() async {
        state.isLoading = true
        state.error = nil

        do {
            let descriptor = FetchDescriptor<Trade>(
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let allTrades = try modelContext.fetch(descriptor)
            let tradesByAsset = Dictionary(grouping: allTrades) { $0.asset }

            let symbols = tradesByAsset.keys.map { "\($0)USDT" }
            let prices = try await priceService.fetchPrices(symbols)

            var holdings: [Holding] = []

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

                let result = fifoCalculator.calculate(fifoTrades)
                guard result.totalRemainingQuantity > 0 else { continue }

                let currentPrice = prices["\(asset)USDT"] ?? 0
                let currentValue = result.totalRemainingQuantity * currentPrice
                let unrealizedPnL = currentValue - result.totalInvestedUSDT
                let unrealizedPnLPercent = result.totalInvestedUSDT > 0
                    ? (unrealizedPnL / result.totalInvestedUSDT) * 100 : 0

                holdings.append(Holding(
                    asset: asset,
                    totalQuantity: result.totalRemainingQuantity,
                    weightedAvgBuyPrice: result.weightedAvgBuyPrice,
                    totalInvestedUSDT: result.totalInvestedUSDT,
                    currentPrice: currentPrice,
                    currentValueUSDT: currentValue,
                    unrealizedPnL: unrealizedPnL,
                    unrealizedPnLPercent: unrealizedPnLPercent,
                    realizedPnL: result.realizedPnL
                ))
            }

            state.holdings = holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }
}
