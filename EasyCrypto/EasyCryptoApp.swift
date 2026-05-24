//
//  EasyCryptoApp.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

@main
struct EasyCryptoApp: App {
    private let modelContainer: ModelContainer
    private let keychainService: KeychainService
    private let apiClient: BinanceAPIClient
    private let tradeImportService: TradeImportService
    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator

    init() {
        let container = try! ModelContainer(
            for: Trade.self, SyncMetadata.self
        )
        self.modelContainer = container

        let keychain = KeychainService.live()
        self.keychainService = keychain

        let client = BinanceAPIClient.live(keychain: keychain)
        self.apiClient = client

        self.tradeImportService = .live(apiClient: client)
        self.priceService = .live(apiClient: client)
        self.fifoCalculator = .live
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                keychainService: keychainService,
                apiClient: apiClient,
                tradeImportService: tradeImportService,
                priceService: priceService,
                fifoCalculator: fifoCalculator,
                modelContainer: modelContainer
            )
            .preferredColorScheme(.dark)
        }
    }
}
