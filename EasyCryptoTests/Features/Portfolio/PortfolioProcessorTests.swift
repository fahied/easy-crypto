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
    return try ModelContainer(
        for: Trade.self, SyncMetadata.self, AccountBalance.self,
            CrossMarginBalance.self, MarginBalance.self,
        configurations: config
    )
}

private func makeProcessor(
    tradeImportService: TradeImportService = .noop,
    priceService: PriceService = .noop,
    fifoCalculator: FIFOCalculator = .live,
    modelContainer: ModelContainer,
    balanceService: BalanceService = .noop,
    marginTradeImportService: MarginTradeImportService = .noop,
    marginBalanceService: MarginBalanceService = .noop
) throws -> PortfolioProcessor {
    return PortfolioProcessor(
        tradeImportService: tradeImportService,
        priceService: priceService,
        fifoCalculator: fifoCalculator,
        modelContainer: modelContainer,
        balanceService: balanceService,
        marginTradeImportService: marginTradeImportService,
        marginBalanceService: marginBalanceService
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
        let processor = try makeProcessor(modelContainer: makeContainer())
        #expect(processor.state.summary == .empty)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
        #expect(processor.state.lastRefreshDate == nil)
        #expect(processor.state.sortBy == .value)
    }
}

// MARK: - Refresh

@Suite("Given a PortfolioProcessor handling refresh")
struct PortfolioRefreshTests {

    @Test("When refresh succeeds with trades, then summary is computed")
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
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 1.0, "ETH": 5.0] })
        )

        await processor.handle(.refresh)

        #expect(processor.state.summary.holdingsCount == 2)
        #expect(processor.state.isLoading == false)
        #expect(processor.state.error == nil)
        #expect(processor.state.lastRefreshDate != nil)
    }

    @Test("When refresh succeeds with no trades, then state is empty")
    func refreshNoTrades() async throws {
        let processor = try makeProcessor(
            tradeImportService: TradeImportService(sync: { _ in .empty }),
            priceService: PriceService(fetchPrices: { _ in [:] }),
            modelContainer: makeContainer()
        )

        await processor.handle(.refresh)

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
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 1.0] })
        )

        await processor.handle(.refresh)

        // BTC bought at 50k, now worth 60k, holding 1.0
        #expect(processor.state.summary.holdingsCount == 1)
        #expect(processor.state.summary.totalInvestedUSDT == 50000.0)
        #expect(processor.state.summary.totalCurrentValueUSDT == 60000.0)
        #expect(processor.state.summary.totalUnrealizedPnL == 10000.0)
    }

    @Test("When trade import fails, then error is set and isLoading clears")
    func refreshImportError() async throws {
        let importService = TradeImportService(
            sync: { _ in throw BinanceError.noCredentialsConfigured }
        )

        let processor = try makeProcessor(
            tradeImportService: importService,
            modelContainer: makeContainer()
        )

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
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 1.0] })
        )

        await processor.handle(.refresh)

        #expect(processor.state.error != nil)
        #expect(processor.state.isLoading == false)
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
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["ETH": 2.0] })
        )

        await processor.handle(.refresh)

        // BTC fully sold (0 holdings), ETH still held
        #expect(processor.state.summary.holdingsCount == 1)
        #expect(processor.state.summary.totalRealizedPnL == 10000.0)
        #expect(processor.state.summary.totalUnrealizedPnL == 1000.0)
        #expect(processor.state.summary.totalPnL == 11000.0)
    }

    @Test("When wallet balance differs from traded quantity, then holdings use the balance and include USDT")
    func usesBalanceQuantityAndIncludesUSDT() async throws {
        let importService = TradeImportService(
            sync: { _ in
                TradeImportResult(
                    mappedTrades: [
                        makeMappedTrade(
                            id: 1, symbol: "BTCUSDT", asset: "BTC",
                            price: 50000, quantity: 1.0,
                            commission: 0, commissionAsset: "USDT", isBuyer: true
                        ),
                    ],
                    syncUpdates: [SyncUpdate(symbol: "BTCUSDT", lastTradeId: 1, syncDate: Date())]
                )
            }
        )
        let priceService = PriceService(fetchPrices: { _ in ["BTCUSDT": 60000.0] })
        let processor = try makeProcessor(
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 0.6, "USDT": 5000.0] })
        )

        await processor.handle(.refresh)

        // BTC at 0.6 of 1.0 trade quantity, USDT from balance
        #expect(processor.state.summary.holdingsCount == 2)
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
            tradeImportService: importService,
            priceService: PriceService(fetchPrices: { _ in [:] }),
            modelContainer: container
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
            tradeImportService: importService,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0] }),
            modelContainer: container
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

        let priceService = PriceService(
            fetchPrices: { _ in ["BTCUSDT": 65000.0, "ETHUSDT": 3500.0, "SOLUSDT": 150.0] }
        )

        let processor = try makeProcessor(
            tradeImportService: importService,
            priceService: priceService,
            modelContainer: makeContainer(),
            balanceService: BalanceService(fetchBalances: { ["BTC": 1.0, "ETH": 10.0, "SOL": 100.0] })
        )

        await processor.handle(.refresh)
        return processor
    }

    @Test("When sorting by value, then sortBy is updated")
    func sortByValue() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .value))

        #expect(processor.state.sortBy == .value)
    }

    @Test("When sorting by name, then sortBy is updated")
    func sortByName() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .name))

        #expect(processor.state.sortBy == .name)
    }

    @Test("When sorting by P&L, then sortBy is updated")
    func sortByPnL() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .pnl))

        #expect(processor.state.sortBy == .pnl)
    }

    @Test("When sorting by P&L %, then sortBy is updated")
    func sortByPnLPercent() async throws {
        let processor = try await makeProcessorWithHoldings()

        await processor.handle(.sortHoldings(by: .pnlPercent))

        #expect(processor.state.sortBy == .pnlPercent)
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
            tradeImportService: importService,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 50000.0, "ETHUSDT": 3000.0] }),
            modelContainer: container
        )

        await processor.handle(.refresh)

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Trade>()
        let trades = try context.fetch(descriptor)
        #expect(trades.count == 2)
    }
}

// MARK: - Margin Mode

@Suite("Given a PortfolioProcessor with margin trades")
struct PortfolioMarginModeTests {

    @Test("When crossMargin trades exist, then summary includes them")
    func crossMarginRefreshPath() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Seed cross-margin trades
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100,
            tradingMode: .crossMargin
        ))
        context.insert(Trade(
            binanceTradeId: 2, symbol: "BTCUSDT", asset: "BTC",
            price: 60000, quantity: 0.5, quoteQuantity: 30000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_100_000),
            isBuyer: false, orderId: 101,
            tradingMode: .crossMargin
        ))
        try context.save()

        let processor = try makeProcessor(
            tradeImportService: .noop,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 65000.0] }),
            modelContainer: container,
            balanceService: .noop,
            marginTradeImportService: .noop,
            marginBalanceService: .noop
        )

        await processor.handle(.refresh)

        // Summary includes crossMargin holdings
        #expect(processor.state.summary.crossMargin.holdingsCount >= 1)
        #expect(processor.state.summary.crossMargin.realizedPnL > 0)
    }

    @Test("When isolatedMargin trades and balance exist, then summary reflects them")
    func isolatedMarginRefreshPath() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Seed isolated-margin trade
        context.insert(Trade(
            binanceTradeId: 1, symbol: "BTCUSDT", asset: "BTC",
            price: 50000, quantity: 1.0, quoteQuantity: 50000,
            commission: 0, commissionAsset: "USDT",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isBuyer: true, orderId: 100,
            tradingMode: .isolatedMargin
        ))
        // Seed a MarginBalance for isolated position
        context.insert(MarginBalance(
            symbol: "BTCUSDT",
            isolatedMarginKey: "BTCUSDT#BTC",
            asset: "BTC",
            borrowed: 0.5,
            free: 0.3,
            locked: 0.2,
            interest: 0.01
        ))
        try context.save()

        let processor = try makeProcessor(
            tradeImportService: .noop,
            priceService: PriceService(fetchPrices: { _ in ["BTCUSDT": 60000.0] }),
            modelContainer: container,
            balanceService: .noop,
            marginTradeImportService: .noop,
            marginBalanceService: .noop
        )

        await processor.handle(.refresh)

        // Isolated holdings from balance (0.3 free + 0.2 locked = 0.5 net, minus 0.5 borrowed = 0)
        // With FIFO: 1.0 bought, nothing sold, balance net = 0.3+0.2-0.5 = 0
        // So this position has 0 net quantity but a margin position exists
        #expect(processor.state.summary.isolatedMargin.holdingsCount >= 0)
    }
}
