//
//  SyncMetadataTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
import SwiftData
@testable import EasyCrypto

@Suite("Given a SyncMetadata SwiftData model")
struct SyncMetadataTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Trade.self, SyncMetadata.self, configurations: config)
    }

    @Test("When created with valid fields, then all properties are set correctly")
    func creationWithValidFields() {
        let date = Date()
        let metadata = SyncMetadata(symbol: "BTCUSDT", lastTradeId: 12345, lastSyncDate: date)

        #expect(metadata.symbol == "BTCUSDT")
        #expect(metadata.lastTradeId == 12345)
        #expect(metadata.lastSyncDate == date)
    }

    @Test("When inserted into SwiftData, then it persists and can be fetched")
    @MainActor
    func persistenceRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let metadata = SyncMetadata(symbol: "ETHUSDT", lastTradeId: 500, lastSyncDate: Date())
        context.insert(metadata)
        try context.save()

        let descriptor = FetchDescriptor<SyncMetadata>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        let first = try #require(fetched.first)
        #expect(first.symbol == "ETHUSDT")
        #expect(first.lastTradeId == 500)
    }

    @Test("When fetched by symbol, then returns correct metadata")
    @MainActor
    func fetchBySymbol() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(SyncMetadata(symbol: "BTCUSDT", lastTradeId: 100, lastSyncDate: Date()))
        context.insert(SyncMetadata(symbol: "ETHUSDT", lastTradeId: 200, lastSyncDate: Date()))
        try context.save()

        let symbol = "ETHUSDT"
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate<SyncMetadata> { $0.symbol == symbol }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.lastTradeId == 200)
    }

    @Test("When lastTradeId is updated, then save persists the change")
    @MainActor
    func updateLastTradeId() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let metadata = SyncMetadata(symbol: "BTCUSDT", lastTradeId: 100, lastSyncDate: Date())
        context.insert(metadata)
        try context.save()

        metadata.lastTradeId = 999
        metadata.lastSyncDate = Date()
        try context.save()

        let descriptor = FetchDescriptor<SyncMetadata>()
        let fetched = try context.fetch(descriptor)
        let first = try #require(fetched.first)
        #expect(first.lastTradeId == 999)
    }
}
