//
//  PortfolioProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
}

private func makeProcessor(
    importService: TradeImportService = .noop,
    priceService: PriceService = .noop,
    fifoCalculator: FIFOCalculator = .live,
    container: ModelContainer? = nil
) throws -> PortfolioProcessor {
    let container = try container ?? makeContainer()
    return PortfolioProcessor(
        tradeImportService: importService,
        priceService: priceService,
        fifoCalculator: fifoCalculator,
        modelContainer: container
    )
}

private func makeMappedTrade(
    id: Int64 = 1,
    symbol: String = "BTCUSDT",
    asset: String = "BTC",
    price: Double = 50000,
    quantity: Double = 1.0,
    quoteQuantity: Double = 50000,
    commission: Double = 0.001,
    commissionAsset: String = "BTC",
    isBuyer: Bool = true,
    orderId: Int64 = 100
) -> MappedTrade {
    MappedTrade(
        binanceTradeId: id,
        symbol: symbol,
        asset: asset,
        price: price,
        quantity: quantity,
        quoteQuantity: quoteQuantity,
        commission: commission,
        commissionAsset: commissionAsset,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
        isBuyer: isBuyer,
        orderId: orderId
    )
}

// MARK: - Initial State

@Suite("Given a PortfolioProcessor with initial state")
struct PortfolioInitialStateTests {

    @Test("Then state has empty defaults")
    func initialState() throws {
        let processor = try makeProcessor()
        #expect(processor.state.holdings.isEmpty)
        #expect(processor.state.summary == .empty)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
        #expect(processor.state.lastRefreshDate == nil)
        #expect(processor.state.sortCriteria == .value)
    }
}

// MARK: - Refresh

@Suite("Given a PortfolioProcessor handling refresh")
struct PortfolioRefreshTests {

    @Test("When refresh succeeds with trades, then holdings and summary are computed")
    func refreshWithTrades() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(id: 1, symbol: "BTCUSDT", asset: "BTC", price: 50000, quantity: 1.0),
                        makeMappedTrade(id: 2, symbol: "ETHUSDT", asset: "ETH", price: 3000, quantity: 5.0),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                        SyncUpdate(symbol: "ETHUSDT", lastTradeId: 2, syncDate: Date()),
                    ]
                )
            }
        )

        let priceService = PriceService(
            fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0] }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)

        #expect(processor.state.holdings.count == 2)
        #expect(processor.state.summary.holdingsCount == 2)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
        #expect(processor.state.lastRefreshDate != nil)
    }

    @Test("When refresh succeeds with no trades, then state is empty")
    func refreshNoTrades() async throws {
        let processor = try makeProcessor(
            importService: TradeImportService(sync: { _ in .empty }),
            priceService: PriceService(fetchPrices: { _ in [:] })
        )

        await processor.handle(.refresh)

        #expect(processor.state.holdings.isEmpty)
        #expect(processor.state.summary == .empty)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
    }

    @Test("When refresh computes P&L correctly for a single asset")
    func refreshComputesPnL() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(
                            id: 1, symbol: "BTCUSDT", asset: "BTC",
                            price: 50000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT"
                        ),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                    ]
                )
            }
        )

        let priceService = PriceService(
            fetchPrices: { _ in ["BTCUSDT": 60000.0] }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)

        let btc = try #require(processor.state.holdings.first { $0.asset == "BTC" })
        #expect(btc.totalQuantity == 1.0)
        #expect(btc.weightedAvgBuyPrice == 50000.0)
        #expect(btc.currentPrice == 60000.0)
        #expect(btc.currentValueUSDT == 60000.0)
        #expect(btc.unrealizedPnL == 10000.0)
        #expect(btc.totalInvestedUSDT == 50000.0)
    }

    @Test("When trade import fails, then error is set and isLoading clears")
    func refreshImportError() async throws {
        let importService = TradeImportService(
            sync: { _ in throw BinanceError.noCredentialsConfigured }
        )

        let processor = try makeProcessor(importService: importService)

        await processor.handle(.refresh)

        #expect(processor.state.error != nil)
        #expect(processor.state.isLoading == false)
    }

    @Test("When price fetch fails, then error is set")
    func refreshPriceError() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [makeMappedTrade()],
                    syncUpdates: [SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date())]
                )
            }
        )

        let priceService = PriceService(
            fetchPrices: { _ in throw BinanceError.networkError(underlying: URLError(.notConnectedToInternet)) }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)

        #expect(processor.state.error != nil)
        #expect(processor.state.isLoading == false)
    }

    @Test("When assets have zero remaining quantity, then they are excluded from holdings")
    func zeroQuantityExcluded() async throws {
        // Buy 1 BTC then sell 1 BTC → zero remaining
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(
                            id: 1, symbol: "BTCUSDT", asset: "BTC",
                            price: 50000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT", isBuyer: true
                        ),
                        makeMappedTrade(
                            id: 2, symbol: "BTCUSDT", asset: "BTC",
                            price: 60000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT", isBuyer: false
                        ),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 2, syncDate: Date()),
                    ]
                )
            }
        )

        let priceService = PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0] })

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)

        #expect(processor.state.holdings.isEmpty)
    }

    @Test("When a position is fully closed, then summary keeps realized P&L from transaction history")
    func closedPositionsContributeToSummaryRealizedPnL() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(
                            id: 1, symbol: "BTCUSDT", asset: "BTC",
                            price: 50000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT", isBuyer: true
                        ),
                        makeMappedTrade(
                            id: 2, symbol: "BTCUSDT", asset: "BTC",
                            price: 60000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT", isBuyer: false
                        ),
                        makeMappedTrade(
                            id: 3, symbol: "ETHUSDT", asset: "ETH",
                            price: 3000, quantity: 2.0,
                            quoteQuantity: 6000,
                            commission: 0, commissionAsset: "USDT", isBuyer: true
                        ),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 2, syncDate: Date()),
                        SyncUpdate(symbol: "ETHUSDT", lastTradeId: 3, syncDate: Date()),
                    ]
                )
            }
        )

        let priceService = PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0] })

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)

        #expect(processor.state.holdings.count == 1)
        #expect(processor.state.summary.holdingsCount == 1)
        #expect(processor.state.summary.totalRealizedPnL == 10000.0)
        #expect(processor.state.summary.totalUnrealizedPnL == 1000.0)
        #expect(processor.state.summary.totalPnL == 11000.0)
    }
}

// MARK: - Incremental Sync

@Suite("Given a PortfolioProcessor with existing sync metadata")
struct PortfolioIncrementalSyncTests {

    @Test("When refreshing, then existing lastTradeId is passed to import service")
    func incrementalSyncUsesExistingMetadata() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(SyncMetadata(symbol: "BTCUSDT", lastTradeId: 42, lastSyncDate: Date()))
        try context.save()

        var capturedSyncMap: [String: Int64]?
        let importService = TradeImportService(
            sync: { syncMap in
                capturedSyncMap = syncMap
                return .empty
            }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: PriceService(fetchPrices: { _ in [:] }),
            container: container
        )

        await processor.handle(.refresh)

        let map = try #require(capturedSyncMap)
        #expect(map["BTCUSDT"] == 42)
    }

    @Test("When new trades arrive, then sync metadata is updated")
    func syncMetadataUpdated() async throws {
        let container = try makeContainer()

        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [makeMappedTrade(id: 10, symbol: "BTCUSDT", asset: "BTC")],
                    syncUpdates: [SyncUpdate(symbol: "BTCUSDT", lastTradeId: 10, syncDate: Date())]
                )
            }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0] }),
            container: container
        )

        await processor.handle(.refresh)

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SyncMetadata>()
        let metadata = try context.fetch(descriptor)
        let btcMeta = try #require(metadata.first { $0.symbol == "BTCUSDT" })
        #expect(btcMeta.lastTradeId == 10)
    }
}

// MARK: - Sorting

@Suite("Given a PortfolioProcessor with holdings")
struct PortfolioSortTests {

    private func makeProcessorWithHoldings() async throws -> PortfolioProcessor {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(id: 1, symbol: "BTCUSDT", asset: "BTC",
                                        price: 50000, quantity: 1.0,
                                        commission: 0, commissionAsset: "USDT"),
                        makeMappedTrade(id: 2, symbol: "ETHUSDT", asset: "ETH",
                                        price: 3000, quantity: 10.0,
                                        commission: 0, commissionAsset: "USDT"),
                        makeMappedTrade(id: 3, symbol: "SOLUSDT", asset: "SOL",
                                        price: 100, quantity: 100.0,
                                        commission: 0, commissionAsset: "USDT"),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                        SyncUpdate(symbol: "ETHUSDT", lastTradeId: 2, syncDate: Date()),
                        SyncUpdate(symbol: "SOLUSDT", lastTradeId: 3, syncDate: Date()),
                    ]
                )
            }
        )

        // BTC: invested 50000, current 65000 (PnL +15000, +30%)
        // ETH: invested 30000, current 35000 (PnL +5000, +16.7%)
        // SOL: invested 10000, current 15000 (PnL +5000, +50%)
        let priceService = PriceService(
            fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0, "SOLUSDT": 150.0] }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: priceService
        )

        await processor.handle(.refresh)
        return processor
    }

    @Test("When sorting by value, then holdings are ordered by currentValueUSDT descending")
    func sortByValue() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .value))

        let assets = processor.state.holdings.map(\.asset)
        #expect(assets.first == "BTC")  // 65000 > 35000 > 15000
    }

    @Test("When sorting by name, then holdings are ordered alphabetically")
    func sortByName() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .name))

        let assets = processor.state.holdings.map(\.asset)
        #expect(assets == ["BTC", "ETH", "SOL"])
    }

    @Test("When sorting by P&L, then holdings are ordered by unrealizedPnL descending")
    func sortByPnL() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .pnl))

        let assets = processor.state.holdings.map(\.asset)
        #expect(assets.first == "BTC")  // +15000 > +5000
    }

    @Test("When sorting by P&L %, then holdings are ordered by unrealizedPnLPercent descending")
    func sortByPnLPercent() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .pnlPercent))

        let assets = processor.state.holdings.map(\.asset)
        #expect(assets.first == "SOL")  // +50% > +30% > +16.7%
    }

    @Test("When sorting, then sort criteria is updated in state")
    func sortCriteriaUpdated() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .name))

        #expect(processor.state.sortCriteria == .name)
    }
}

// MARK: - Trades Persisted

@Suite("Given a PortfolioProcessor persisting trades")
struct PortfolioTradesPersistenceTests {

    @Test("When refresh imports trades, then trades are persisted to SwiftData")
    func tradesPersisted() async throws {
        let container = try makeContainer()

        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(id: 1, symbol: "BTCUSDT", asset: "BTC"),
                        makeMappedTrade(id: 2, symbol: "ETHUSDT", asset: "ETH"),
                    ],
                    syncUpdates: [
                        SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date()),
                        SyncUpdate(symbol: "ETHUSDT", lastTradeId: 2, syncDate: Date()),
                    ]
                )
            }
        )

        let processor = try makeProcessor(
            importService: importService,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0, "ETHUSDT": 3000.0] }),
            container: container
        )

        await processor.handle(.refresh)

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Trade>()
        let trades = try context.fetch(descriptor)
        #expect(trades.count == 2)
    }
}
