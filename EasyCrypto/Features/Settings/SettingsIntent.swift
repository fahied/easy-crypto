//
//  SettingsIntent.swift
//  EasyCrypto
//

import Foundation

enum ConnectionStatus: Sendable {
    case idle
    case testing
    case success
    case failed(String)
}

enum SettingsIntent: Intent {
    case saveApiKey(apiKey: String, secret: String)
    case deleteApiKey
    case testConnection
    case clearAllData
    case loadCredentials
}
