//
//  EasyCryptoApp.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct EasyCryptoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer: ModelContainer
    private let keychainService: KeychainService
    private let apiClient: BinanceAPIClient
    private let tradeImportService: TradeImportService
    private let priceService: PriceService
    private let fifoCalculator: FIFOCalculator
    private let notificationService: NotificationService
    private let priceAlertService: PriceAlertService
    private let candleAlertService: CandleAlertService

    init() {
        let container = try! ModelContainer(
            for: Trade.self, SyncMetadata.self, PriceAlertConfig.self, NotificationLogEntry.self,
            CandleAlertState.self, AccountBalance.self, TradingInsight.self, InsightState.self
        )
        self.modelContainer = container

        let keychain = KeychainService.live()
        self.keychainService = keychain

        let client = BinanceAPIClient.live(keychain: keychain)
        self.apiClient = client

        let prices = PriceService.live(apiClient: client)
        let fifo = FIFOCalculator.live
        self.tradeImportService = .live(apiClient: client)
        self.priceService = prices
        self.fifoCalculator = fifo

        let notifications = NotificationService.live
        self.notificationService = notifications
        self.priceAlertService = .live(
            priceService: prices,
            fifoCalculator: fifo,
            notificationService: notifications
        )
        self.candleAlertService = .live(
            fetchKlines: client.fetchKlines,
            notificationService: notifications
        )

        Self.registerBackgroundRefresh(
            container: container,
            service: self.priceAlertService,
            candleService: self.candleAlertService
        )
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Self.scheduleAppRefresh()
            }
        }
    }

    // MARK: - Background Refresh

    private static func registerBackgroundRefresh(
        container: ModelContainer,
        service: PriceAlertService,
        candleService: CandleAlertService
    ) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: PriceAlertRefresher.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handle(task: refreshTask, container: container, service: service, candleService: candleService)
        }
    }

    /// Schedules the next background refresh. iOS treats `earliestBeginDate` as a
    /// hint; actual wake cadence is decided by the system.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: PriceAlertRefresher.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(
        task: BGAppRefreshTask,
        container: ModelContainer,
        service: PriceAlertService,
        candleService: CandleAlertService
    ) {
        // Always queue the next refresh so the chain continues.
        scheduleAppRefresh()

        let work = Task { @MainActor in
            do {
                let context = ModelContext(container)
                try await PriceAlertRefresher.run(
                    modelContext: context,
                    alertService: service
                )
                try await CandleAlertRefresher.run(
                    modelContext: context,
                    candleService: candleService
                )
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
