//
//  TradeHistoryProcessor.swift
//  EasyCrypto
//

import Foundation
import SwiftData
import Observation

@Observable
class TradeHistoryProcessor: Processor {
    var state = TradeHistoryState()

    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func handle(_ intent: TradeHistoryIntent) async {
        switch intent {
        case .loadHistory:
            await loadHistory()
        case .filterByCoin(let coin):
            await filterByCoin(coin)
        }
    }

    private func loadHistory() async {
        state.isLoading = true
        state.error = nil

        do {
            let allTrades = try fetchTrades(for: nil)
            state.trades = allTrades
            state.availableCoins = discoverCoins(from: allTrades)
            state.selectedCoin = nil
        } catch {
            state.error = error.localizedDescription
        }

        state.isLoading = false
    }

    private func filterByCoin(_ coin: String?) async {
        state.selectedCoin = coin
        state.error = nil

        do {
            state.trades = try fetchTrades(for: coin)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func fetchTrades(for coin: String?) throws -> [Trade] {
        var descriptor: FetchDescriptor<Trade>

        if let coin {
            let predicate = #Predicate<Trade> { $0.asset == coin }
            descriptor = FetchDescriptor<Trade>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<Trade>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        return try modelContext.fetch(descriptor)
    }

    private func discoverCoins(from trades: [Trade]) -> [String] {
        Array(Set(trades.map(\.asset))).sorted()
    }
}
