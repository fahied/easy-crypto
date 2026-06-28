//
//  AccountBalanceTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given an AccountBalance")
@MainActor
struct AccountBalanceTests {

    @Test("When inserted, then it round-trips through an in-memory container")
    func roundTrips() throws {
        let container = try ModelContainer(
            for: AccountBalance.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(AccountBalance(asset: "BTC", quantity: 0.6, updatedAt: updatedAt))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AccountBalance>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.asset == "BTC")
        #expect(fetched.first?.quantity == 0.6)
        #expect(fetched.first?.updatedAt == updatedAt)
    }
}
