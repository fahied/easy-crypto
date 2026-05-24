//
//  KeychainServiceTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing
@testable import EasyCrypto

// MARK: - Unit Tests (mock-based, parallel-safe)

@Suite("Given a KeychainService with mock closures")
struct KeychainServiceMockTests {

    @Test("When save is called, then it invokes the save closure with correct credentials")
    func saveInvokesClosure() throws {
        var capturedKey: String?
        var capturedSecret: String?

        let service = KeychainService(
            save: { key, secret in
                capturedKey = key
                capturedSecret = secret
            },
            load: { nil },
            delete: { }
        )

        try service.save("myApiKey", "mySecret")
        #expect(capturedKey == "myApiKey")
        #expect(capturedSecret == "mySecret")
    }

    @Test("When load returns credentials, then they match what was provided")
    func loadReturnsMockCredentials() throws {
        let expected = KeychainCredentials(apiKey: "key123", secret: "secret456")
        let service = KeychainService(
            save: { _, _ in },
            load: { expected },
            delete: { }
        )

        let result = try service.load()
        #expect(result == expected)
    }

    @Test("When load has no stored credentials, then it returns nil")
    func loadReturnsNil() throws {
        let service = KeychainService(
            save: { _, _ in },
            load: { nil },
            delete: { }
        )

        let result = try service.load()
        #expect(result == nil)
    }

    @Test("When delete is called, then it invokes the delete closure")
    func deleteInvokesClosure() throws {
        var deleteCalled = false
        let service = KeychainService(
            save: { _, _ in },
            load: { nil },
            delete: { deleteCalled = true }
        )

        try service.delete()
        #expect(deleteCalled)
    }

    @Test("When save throws, then error propagates to caller")
    func saveThrowsPropagates() {
        let service = KeychainService(
            save: { _, _ in throw KeychainError.saveFailed(status: -1) },
            load: { nil },
            delete: { }
        )

        #expect(throws: KeychainError.self) {
            try service.save("key", "secret")
        }
    }

    @Test("When load throws, then error propagates to caller")
    func loadThrowsPropagates() {
        let service = KeychainService(
            save: { _, _ in },
            load: { throw KeychainError.loadFailed(status: -1) },
            delete: { }
        )

        #expect(throws: KeychainError.self) {
            _ = try service.load()
        }
    }
}

// MARK: - KeychainCredentials Tests

@Suite("Given KeychainCredentials")
struct KeychainCredentialsTests {

    @Test("When created with key and secret, then properties are set")
    func creation() {
        let creds = KeychainCredentials(apiKey: "abc", secret: "xyz")
        #expect(creds.apiKey == "abc")
        #expect(creds.secret == "xyz")
    }

    @Test("When two credentials have same values, then they are equal")
    func equatable() {
        let a = KeychainCredentials(apiKey: "k", secret: "s")
        let b = KeychainCredentials(apiKey: "k", secret: "s")
        #expect(a == b)
    }

    @Test("When credentials differ, then they are not equal")
    func notEqual() {
        let a = KeychainCredentials(apiKey: "k1", secret: "s")
        let b = KeychainCredentials(apiKey: "k2", secret: "s")
        #expect(a != b)
    }
}

// MARK: - KeychainError Tests

@Suite("Given KeychainError")
struct KeychainErrorTests {

    @Test("When saveFailed, then localized description contains status")
    func saveFailedDescription() {
        let error = KeychainError.saveFailed(status: -25299)
        #expect(error.errorDescription?.contains("-25299") == true)
    }

    @Test("When loadFailed, then localized description contains status")
    func loadFailedDescription() {
        let error = KeychainError.loadFailed(status: -25300)
        #expect(error.errorDescription?.contains("-25300") == true)
    }

    @Test("When deleteFailed, then localized description contains status")
    func deleteFailedDescription() {
        let error = KeychainError.deleteFailed(status: -25244)
        #expect(error.errorDescription?.contains("-25244") == true)
    }

    @Test("When dataConversionFailed, then it has a description")
    func dataConversionDescription() {
        let error = KeychainError.dataConversionFailed
        #expect(error.errorDescription != nil)
    }
}

// MARK: - Live Integration Tests (real Keychain, serialized)

@Suite("Given the live KeychainService on simulator", .serialized)
struct KeychainServiceLiveTests {

    private let testService = "com.fahied.EasyCrypto.binance.test"

    private func makeLiveService() -> KeychainService {
        KeychainService.live(service: testService)
    }

    private func cleanupKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test("When saving then loading credentials, then loaded matches saved")
    func saveAndLoad() throws {
        let service = makeLiveService()
        cleanupKeychain()

        try service.save("testKey123", "testSecret456")
        let loaded = try service.load()

        let creds = try #require(loaded)
        #expect(creds.apiKey == "testKey123")
        #expect(creds.secret == "testSecret456")

        cleanupKeychain()
    }

    @Test("When no credentials stored, then load returns nil")
    func loadEmpty() throws {
        let service = makeLiveService()
        cleanupKeychain()

        let loaded = try service.load()
        #expect(loaded == nil)
    }

    @Test("When credentials deleted, then load returns nil")
    func deleteRemovesCredentials() throws {
        let service = makeLiveService()
        cleanupKeychain()

        try service.save("key", "secret")
        try service.delete()
        let loaded = try service.load()
        #expect(loaded == nil)
    }

    @Test("When saving over existing credentials, then new values are loaded")
    func overwriteCredentials() throws {
        let service = makeLiveService()
        cleanupKeychain()

        try service.save("oldKey", "oldSecret")
        try service.save("newKey", "newSecret")

        let loaded = try service.load()
        let creds = try #require(loaded)
        #expect(creds.apiKey == "newKey")
        #expect(creds.secret == "newSecret")

        cleanupKeychain()
    }

    @Test("When deleting non-existent credentials, then it does not throw")
    func deleteNonExistent() throws {
        let service = makeLiveService()
        cleanupKeychain()

        // Should not throw — idempotent delete
        try service.delete()
    }
}
