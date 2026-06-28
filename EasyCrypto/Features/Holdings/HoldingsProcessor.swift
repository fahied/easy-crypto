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

            // FIFO per traded asset for cost basis / realized P&L.
            var fifoByAsset: [String: FIFOResult] = [:]
            for (asset, trades) in tradesByAsset {
                fifoByAsset[asset] = fifoCalculator.calculate(trades.map(Self.toFIFOTrade))
            }

            // Authoritative wallet balances (persisted by the portfolio refresh).
            // Fall back to FIFO remaining quantity when no snapshot exists yet.
            let persisted = try modelContext.fetch(FetchDescriptor<AccountBalance>())
            let quantities: [String: Double]
            if persisted.isEmpty {
                quantities = fifoByAsset.compactMapValues {
                    $0.totalRemainingQuantity > 0 ? $0.totalRemainingQuantity : nil
                }
            } else {
                quantities = Dictionary(
                    persisted.map { ($0.asset, $0.quantity) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            let priceSymbols = quantities.keys.filter { $0 != "USDT" }.map { "\($0)USDT" }
            let prices = try await priceService.fetchPrices(priceSymbols)

            var holdings: [Holding] = []
            for (asset, quantity) in quantities where quantity > 0 {
                let currentPrice = asset == "USDT" ? 1.0 : (prices["\(asset)USDT"] ?? 0)
                holdings.append(HoldingFactory.make(
                    asset: asset,
                    quantity: quantity,
                    currentPrice: currentPrice,
                    fifo: fifoByAsset[asset] ?? .empty
                ))
            }

            state.holdings = holdings.sorted { $0.currentValueUSDT > $1.currentValueUSDT }
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

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
