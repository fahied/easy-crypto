//
//  KeychainService.swift
//  EasyCrypto
//

import Foundation
import Security
import os

// MARK: - Credentials

nonisolated struct KeychainCredentials: Equatable, Sendable, Codable {
    let apiKey: String
    let secret: String
}

// MARK: - Error

nonisolated enum KeychainError: Error, LocalizedError, Sendable {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Keychain save failed with status: \(status)"
        case .loadFailed(let status):
            "Keychain load failed with status: \(status)"
        case .deleteFailed(let status):
            "Keychain delete failed with status: \(status)"
        case .dataConversionFailed:
            "Failed to convert keychain data"
        }
    }
}

// MARK: - Service (struct-with-closures pattern)

nonisolated struct KeychainService: Sendable {
    var save: @Sendable (_ apiKey: String, _ secret: String) throws -> Void
    var load: @Sendable () throws -> KeychainCredentials?
    var delete: @Sendable () throws -> Void
}

// MARK: - Live Implementation

extension KeychainService {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "keychain"
    )

    static func live(service: String = "com.fahied.EasyCrypto.binance") -> KeychainService {
        KeychainService(
            save: { apiKey, secret in
                let credentials = KeychainCredentials(apiKey: apiKey, secret: secret)
                let data = try JSONEncoder().encode(credentials)

                // Delete existing item first (upsert pattern)
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "binance-credentials",
                ]
                SecItemDelete(deleteQuery as CFDictionary)

                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "binance-credentials",
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                ]

                let status = SecItemAdd(addQuery as CFDictionary, nil)
                guard status == errSecSuccess else {
                    logger.error("Keychain save failed: \(status)")
                    throw KeychainError.saveFailed(status: status)
                }
                logger.info("Credentials saved to keychain")
            },
            load: {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "binance-credentials",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]

                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                guard status != errSecItemNotFound else {
                    logger.debug("No credentials found in keychain")
                    return nil
                }
                guard status == errSecSuccess else {
                    logger.error("Keychain load failed: \(status)")
                    throw KeychainError.loadFailed(status: status)
                }
                guard let data = result as? Data else {
                    logger.error("Keychain data conversion failed")
                    throw KeychainError.dataConversionFailed
                }

                let credentials = try JSONDecoder().decode(KeychainCredentials.self, from: data)
                logger.debug("Credentials loaded from keychain")
                return credentials
            },
            delete: {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "binance-credentials",
                ]

                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    logger.error("Keychain delete failed: \(status)")
                    throw KeychainError.deleteFailed(status: status)
                }
                logger.info("Credentials deleted from keychain")
            }
        )
    }

    // MARK: - Preview / Test Values

    static let preview = KeychainService(
        save: { _, _ in },
        load: { KeychainCredentials(apiKey: "preview-key", secret: "preview-secret") },
        delete: { }
    )

    static let noop = KeychainService(
        save: { _, _ in },
        load: { nil },
        delete: { }
    )
}
