//
//  BinanceAPIClient.swift
//  EasyCrypto
//

import CryptoKit
import Foundation
import os

// MARK: - Response DTOs

nonisolated struct BinanceBalance: Equatable, Sendable, Codable {
    let asset: String
    let free: String
    let locked: String
}

nonisolated struct BinanceAccountResponse: Sendable, Codable {
    let balances: [BinanceBalance]
}

nonisolated struct BinanceTrade: Equatable, Sendable, Codable {
    let id: Int64
    let symbol: String
    let price: String
    let qty: String
    let quoteQty: String
    let commission: String
    let commissionAsset: String
    let time: Int64
    let isBuyer: Bool
    let orderId: Int64
}

nonisolated struct BinanceTickerPrice: Equatable, Sendable, Codable {
    let symbol: String
    let price: String
}

nonisolated struct BinanceAPIErrorResponse: Equatable, Sendable, Codable {
    let code: Int
    let msg: String
}

/// Binance kline (candlestick) decoded from the raw JSON array format.
/// Each kline is `[openTime, open, high, low, close, volume, closeTime, ...]`.
nonisolated struct BinanceKline: Sendable {
    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let closeTime: Int64

    var toKline: Kline {
        Kline(
            openTime: openTime,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            closeTime: closeTime
        )
    }
}

// MARK: - Margin DTOs

/// GET /sapi/v1/margin/account — cross-margin account overview.
nonisolated struct BinanceMarginAccount: Sendable, Codable {
    let marginLevel: String
    let totalAssetOfBtc: String
    let totalLiabilityOfBtc: String
    let totalNetAssetOfBtc: String
    let totalAsset: String?
    let totalLiability: String?
    let totalNetAsset: String?
    let maxBorrowable: String?
    let maintained: String?
    let totalCoin: String? = nil

    struct AssetEntry: Sendable, Codable {
        let asset: String?
        let borrowed: String
        let free: String
        let locked: String
        let interest: String
        let netAsset: String
        let netAssetOfBtc: String?
        let maxBorrowable: String?
    }
    let userAssets: [AssetEntry]?
}

/// GET /sapi/v1/margin/isolated/account — per-isolated-symbol account overview.
/// Source of `liquidatePrice`, the only place Binance reports isolated-margin liquidation risk.
nonisolated struct BinanceIsolatedMarginAccount: Sendable, Codable {
    struct AssetDetail: Sendable, Codable {
        let asset: String
        let borrowed: String
        let free: String
        let locked: String
        let interest: String
        let netAsset: String
    }

    struct IsolatedPair: Sendable, Codable, Identifiable {
        let symbol: String
        let marginLevel: String
        let marginRatio: String
        let indexPrice: String
        let liquidatePrice: String
        let liquidateRate: String
        let tradeEnabled: Bool
        let enabled: Bool
        let baseAsset: AssetDetail
        let quoteAsset: AssetDetail

        var id: String { symbol }
    }

    let assets: [IsolatedPair]
    let totalAssetOfBtc: String
    let totalLiabilityOfBtc: String
    let totalNetAssetOfBtc: String

    static let empty = BinanceIsolatedMarginAccount(
        assets: [],
        totalAssetOfBtc: "0",
        totalLiabilityOfBtc: "0",
        totalNetAssetOfBtc: "0"
    )
}

/// GET /sapi/v1/margin/allAssets — all margin assets summary.
nonisolated struct BinanceMarginAsset: Sendable, Codable, Identifiable {
    let asset: String?
    let borrowed: String?
    let free: String?
    let locked: String?
    let netAsset: String?
    let maxBorrowable: String?
    let maintained: String?

    var id: String { asset ?? UUID().uuidString }
}

/// GET /sapi/v1/margin/myTrades — margin trade history.
nonisolated struct BinanceMarginTrade: Equatable, Sendable, Codable {
    let id: Int64
    let symbol: String
    let price: String
    let qty: String
    let quoteQty: String
    let commission: String
    let commissionAsset: String
    let time: Int64
    let isBuyer: Bool
    let orderId: Int64
    let isIsolated: Bool?
    let marginBuyBorrowAmount: String?
    let marginBuyBorrowAsset: String?
}

/// GET /sapi/v1/margin/openOrders — margin open orders.
nonisolated struct BinanceMarginOrder: Sendable, Codable, Identifiable {
    let symbol: String
    let orderId: Int64
    let clientOrderId: String
    let price: String
    let origQty: String
    let executedQty: String
    let cummulativeQuoteQty: String
    let status: String
    let timeInForce: String
    let type: String
    let side: String
    let stopPrice: String
    let icebergQty: String
    let time: Int64
    let updateTime: Int64
    let isIsolated: Bool?

    var id: String { "\(symbol)-\(orderId)" }
}

/// GET /sapi/v1/margin/transfer — isolated-margin transfer history.
nonisolated struct BinanceMarginTransfer: Sendable, Codable, Identifiable {
    let asset: String
    let symbol: String
    let transferType: String
    let amount: String
    let timestamp: Int64
    let status: String
    let tranId: Int64

    var id: String { "\(tranId)" }
}

extension BinanceKline: Decodable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        openTime = try container.decode(Int64.self)
        open = Double(try container.decode(String.self)) ?? 0
        high = Double(try container.decode(String.self)) ?? 0
        low = Double(try container.decode(String.self)) ?? 0
        close = Double(try container.decode(String.self)) ?? 0
        volume = Double(try container.decode(String.self)) ?? 0
        closeTime = try container.decode(Int64.self)
    }
}

// MARK: - Error

nonisolated enum BinanceError: Error, LocalizedError, Sendable {
    case invalidCredentials
    case rateLimited(retryAfterSeconds: Int?)
    case apiError(code: Int, message: String)
    case networkError(underlying: any Error)
    case decodingError(underlying: any Error)
    case noCredentialsConfigured
    case invalidMode(_ mode: String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Invalid API credentials"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                "Rate limited — retry after \(seconds) seconds"
            } else {
                "Rate limited — please try again later"
            }
        case .apiError(let code, let message):
            "Binance API error \(code): \(message)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            "Decoding error: \(error.localizedDescription)"
        case .noCredentialsConfigured:
            "No API credentials configured"
        case .invalidMode(let mode):
            "Operation not valid for trading mode: \(mode)"
        }
    }
}

// MARK: - HMAC Signing

nonisolated enum BinanceSigner {
    static func sign(queryString: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(queryString.utf8),
            using: key
        )
        return Data(signature).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Server Time Sync

nonisolated struct BinanceServerTimeResponse: Sendable, Codable {
    let serverTime: Int64
}

/// Caches the offset between local clock and Binance server clock.
/// Thread-safe via actor isolation.
actor BinanceTimeSynchronizer {
    private var offsetMs: Int64 = 0
    private var lastSyncDate: Date?
    private let session: URLSession
    private let syncInterval: TimeInterval = 300 // re-sync every 5 minutes

    init(session: URLSession = .shared) {
        self.session = session
    }

    func adjustedTimestamp() async -> Int64 {
        if lastSyncDate == nil || Date().timeIntervalSince(lastSyncDate!) > syncInterval {
            await syncServerTime()
        }
        return Int64(Date().timeIntervalSince1970 * 1000) + offsetMs
    }

    private func syncServerTime() async {
        guard let url = URL(string: "https://api.binance.com/api/v3/time") else { return }
        do {
            let localBefore = Int64(Date().timeIntervalSince1970 * 1000)
            let (data, _) = try await session.data(for: URLRequest(url: url))
            let localAfter = Int64(Date().timeIntervalSince1970 * 1000)
            let serverTime = try JSONDecoder().decode(BinanceServerTimeResponse.self, from: data)
            let localMid = (localBefore + localAfter) / 2
            offsetMs = serverTime.serverTime - localMid
            lastSyncDate = Date()
        } catch {
            // If sync fails, keep previous offset (0 on first failure)
        }
    }
}

// MARK: - URL Builder

nonisolated enum BinanceURLBuilder {
    static let baseURL = "https://api.binance.com"

    static func buildSignedURL(
        path: String,
        params: [(String, String)] = [],
        secret: String,
        timestamp: Int64
    ) -> URL? {
        var allParams = params
        allParams.append(("timestamp", String(timestamp)))
        let queryString = allParams
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        let signature = BinanceSigner.sign(queryString: queryString, secret: secret)
        return URL(string: "\(baseURL)\(path)?\(queryString)&signature=\(signature)")
    }

    static func buildPublicURL(
        path: String,
        params: [(String, String)] = []
    ) -> URL? {
        if params.isEmpty {
            return URL(string: "\(baseURL)\(path)")
        }
        let queryString = params
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        return URL(string: "\(baseURL)\(path)?\(queryString)")
    }
}

// MARK: - Response Mapper

nonisolated enum BinanceResponseMapper {
    static func mapResponse(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinanceError.networkError(underlying: URLError(.badServerResponse))
        }
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw BinanceError.invalidCredentials
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
            throw BinanceError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            if let apiError = try? JSONDecoder().decode(
                BinanceAPIErrorResponse.self,
                from: data
            ) {
                throw BinanceError.apiError(code: apiError.code, message: apiError.msg)
            }
            throw BinanceError.apiError(
                code: httpResponse.statusCode,
                message: "Unknown error"
            )
        }
    }
}

// MARK: - Client (struct-with-closures pattern)

nonisolated struct BinanceAPIClient: Sendable {
    var fetchAccount: @Sendable () async throws -> [BinanceBalance]
    var fetchMyTrades: @Sendable (_ symbol: String, _ fromId: Int64?) async throws -> [BinanceTrade]
    var fetchTickerPrices: @Sendable (_ symbols: [String]) async throws -> [BinanceTickerPrice]
    var fetchKlines: @Sendable (_ symbol: String, _ interval: String, _ limit: Int) async throws -> [Kline]

    // MARK: - Margin Closures
    var fetchMarginAccount: @Sendable () async throws -> BinanceMarginAccount
    var fetchIsolatedMarginAccount: @Sendable (_ symbols: [String]) async throws -> BinanceIsolatedMarginAccount
    var fetchMarginMyTrades: @Sendable (_ symbol: String, _ fromId: Int64?, _ isIsolated: Bool) async throws -> [BinanceMarginTrade]
    var fetchMarginOpenOrders: @Sendable (_ symbol: String, _ isIsolated: Bool) async throws -> [BinanceMarginOrder]
    var fetchMarginAllAssets: @Sendable () async throws -> [BinanceMarginAsset]
    var fetchIsolatedMarginTransfers: @Sendable (_ symbol: String) async throws -> [BinanceMarginTransfer]

    init(
        fetchAccount: @escaping @Sendable () async throws -> [BinanceBalance],
        fetchMyTrades: @escaping @Sendable (_ symbol: String, _ fromId: Int64?) async throws -> [BinanceTrade],
        fetchTickerPrices: @escaping @Sendable (_ symbols: [String]) async throws -> [BinanceTickerPrice],
        fetchKlines: @escaping @Sendable (_ symbol: String, _ interval: String, _ limit: Int) async throws -> [Kline],
        fetchMarginAccount: @escaping @Sendable () async throws -> BinanceMarginAccount,
        // Defaulted: predates this closure, existing call sites don't need updating (ADV-CORE-SERVICES-005).
        fetchIsolatedMarginAccount: @escaping @Sendable (_ symbols: [String]) async throws -> BinanceIsolatedMarginAccount = { _ in .empty },
        fetchMarginMyTrades: @escaping @Sendable (_ symbol: String, _ fromId: Int64?, _ isIsolated: Bool) async throws -> [BinanceMarginTrade],
        fetchMarginOpenOrders: @escaping @Sendable (_ symbol: String, _ isIsolated: Bool) async throws -> [BinanceMarginOrder],
        fetchMarginAllAssets: @escaping @Sendable () async throws -> [BinanceMarginAsset],
        fetchIsolatedMarginTransfers: @escaping @Sendable (_ symbol: String) async throws -> [BinanceMarginTransfer]
    ) {
        self.fetchAccount = fetchAccount
        self.fetchMyTrades = fetchMyTrades
        self.fetchTickerPrices = fetchTickerPrices
        self.fetchKlines = fetchKlines
        self.fetchMarginAccount = fetchMarginAccount
        self.fetchIsolatedMarginAccount = fetchIsolatedMarginAccount
        self.fetchMarginMyTrades = fetchMarginMyTrades
        self.fetchMarginOpenOrders = fetchMarginOpenOrders
        self.fetchMarginAllAssets = fetchMarginAllAssets
        self.fetchIsolatedMarginTransfers = fetchIsolatedMarginTransfers
    }
}

// MARK: - Live Implementation

extension BinanceAPIClient {
    nonisolated private static let logger = Logger(
        subsystem: "com.fahied.EasyCrypto",
        category: "networking"
    )

    static func live(
        keychain: KeychainService = .live(),
        session: URLSession = .shared
    ) -> BinanceAPIClient {
        let timeSynchronizer = BinanceTimeSynchronizer(session: session)

        return BinanceAPIClient(
            fetchAccount: {
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/api/v3/account",
                    params: [("omitZeroBalances", "true")],
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching account balances")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                BinanceDebugLogger.logJSONResponse(
                    validData,
                    endpoint: "/api/v3/account",
                    logger: logger
                )
                do {
                    let accountResponse = try JSONDecoder().decode(
                        BinanceAccountResponse.self,
                        from: validData
                    )
                    logger.info("Fetched \(accountResponse.balances.count) balances")
                    return accountResponse.balances
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchMyTrades: { symbol, fromId in
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                var params: [(String, String)] = [
                    ("symbol", symbol),
                    ("limit", "1000"),
                ]
                if let fromId {
                    params.append(("fromId", String(fromId)))
                }
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/api/v3/myTrades",
                    params: params,
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching trades for \(symbol)")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                BinanceDebugLogger.logJSONResponse(
                    validData,
                    endpoint: "/api/v3/myTrades?symbol=\(symbol)",
                    logger: logger
                )
                do {
                    let trades = try JSONDecoder().decode(
                        [BinanceTrade].self,
                        from: validData
                    )
                    logger.info("Fetched \(trades.count) trades for \(symbol)")
                    return trades
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchTickerPrices: { symbols in
                let params: [(String, String)]
                if symbols.count == 1 {
                    params = [("symbol", symbols[0])]
                } else {
                    let symbolsList = symbols.map { "%22\($0)%22" }.joined(separator: ",")
                    params = [("symbols", "%5B\(symbolsList)%5D")]
                }
                guard let url = BinanceURLBuilder.buildPublicURL(
                    path: "/api/v3/ticker/price",
                    params: params
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }

                logger.debug("Fetching ticker prices for \(symbols.count) symbols")
                let (data, response) = try await session.data(for: URLRequest(url: url))
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                do {
                    if symbols.count == 1 {
                        let single = try JSONDecoder().decode(
                            BinanceTickerPrice.self,
                            from: validData
                        )
                        return [single]
                    } else {
                        return try JSONDecoder().decode(
                            [BinanceTickerPrice].self,
                            from: validData
                        )
                    }
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchKlines: { symbol, interval, limit in
                let params: [(String, String)] = [
                    ("symbol", symbol),
                    ("interval", interval),
                    ("limit", String(limit)),
                ]
                guard let url = BinanceURLBuilder.buildPublicURL(
                    path: "/api/v3/klines",
                    params: params
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }

                logger.debug("Fetching klines for \(symbol)")
                let (data, response) = try await session.data(for: URLRequest(url: url))
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                do {
                    let bKlines = try JSONDecoder().decode(
                        [BinanceKline].self,
                        from: validData
                    )
                    let klines = bKlines.map(\.toKline)
                    logger.info("Fetched \(klines.count) klines for \(symbol)")
                    return klines
                } catch let error as BinanceError {
                    throw error
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },

            // MARK: - Margin Endpoints

            fetchMarginAccount: {
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/account",
                    params: [],
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching margin account overview")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                BinanceDebugLogger.logJSONResponse(
                    validData,
                    endpoint: "/sapi/v1/margin/account",
                    logger: logger
                )
                do {
                    return try JSONDecoder().decode(
                        BinanceMarginAccount.self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchIsolatedMarginAccount: { symbols in
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                var params: [(String, String)] = []
                if !symbols.isEmpty {
                    params.append(("symbols", symbols.joined(separator: ",")))
                }
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/isolated/account",
                    params: params,
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching isolated margin account for \(symbols.joined(separator: ","))")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                BinanceDebugLogger.logJSONResponse(
                    validData,
                    endpoint: "/sapi/v1/margin/isolated/account",
                    logger: logger
                )
                do {
                    return try JSONDecoder().decode(
                        BinanceIsolatedMarginAccount.self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchMarginMyTrades: { symbol, fromId, isIsolated in
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                var params: [(String, String)] = [
                    ("symbol", symbol),
                    ("limit", "1000"),
                ]
                if let fromId {
                    params.append(("fromId", String(fromId)))
                }
                params.append(("isIsolated", isIsolated ? "TRUE" : "FALSE"))
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/myTrades",
                    params: params,
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching margin trades for \(symbol) isolated=\(isIsolated)")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                BinanceDebugLogger.logJSONResponse(
                    validData,
                    endpoint: "/sapi/v1/margin/myTrades?symbol=\(symbol)&isIsolated=\(isIsolated)",
                    logger: logger
                )
                do {
                    return try JSONDecoder().decode(
                        [BinanceMarginTrade].self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchMarginOpenOrders: { symbol, isIsolated in
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                let params: [(String, String)] = [
                    ("symbol", symbol),
                    ("isIsolated", isIsolated ? "TRUE" : "FALSE"),
                ]
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/openOrders",
                    params: params,
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching margin open orders for \(symbol)")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                do {
                    return try JSONDecoder().decode(
                        [BinanceMarginOrder].self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchMarginAllAssets: {
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/allAssets",
                    params: [],
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching all margin assets")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                do {
                    return try JSONDecoder().decode(
                        [BinanceMarginAsset].self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            },
            fetchIsolatedMarginTransfers: { symbol in
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = await timeSynchronizer.adjustedTimestamp()
                let params: [(String, String)] = [
                    ("asset", symbol),
                ]
                guard let url = BinanceURLBuilder.buildSignedURL(
                    path: "/sapi/v1/margin/transfer",
                    params: params,
                    secret: credentials.secret,
                    timestamp: timestamp
                ) else {
                    throw BinanceError.networkError(underlying: URLError(.badURL))
                }
                var request = URLRequest(url: url)
                request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")

                logger.debug("Fetching isolated margin transfers for \(symbol)")
                let (data, response) = try await session.data(for: request)
                let validData = try BinanceResponseMapper.mapResponse(
                    data: data,
                    response: response
                )
                do {
                    return try JSONDecoder().decode(
                        [BinanceMarginTransfer].self,
                        from: validData
                    )
                } catch {
                    throw BinanceError.decodingError(underlying: error)
                }
            }
        )
    }
}

// MARK: - Preview & Noop

extension BinanceAPIClient {
    static let preview = BinanceAPIClient(
        fetchAccount: { [
            BinanceBalance(asset: "BTC", free: "0.5", locked: "0"),
            BinanceBalance(asset: "ETH", free: "10.0", locked: "0"),
            BinanceBalance(asset: "USDT", free: "5000", locked: "0"),
        ] },
        fetchMyTrades: { _, _ in [
            BinanceTrade(
                id: 1, symbol: "BTCUSDT", price: "50000", qty: "0.5",
                quoteQty: "25000", commission: "0.001", commissionAsset: "BTC",
                time: 1_700_000_000_000, isBuyer: true, orderId: 100
            ),
        ] },
        fetchTickerPrices: { _ in [
            BinanceTickerPrice(symbol: "BTCUSDT", price: "65000.00"),
            BinanceTickerPrice(symbol: "ETHUSDT", price: "3500.00"),
        ] },
        fetchKlines: { _, _, _ in [
            Kline(
                openTime: 1_700_000_000_000, open: 50000, high: 51000,
                low: 49000, close: 50500, volume: 1000,
                closeTime: 1_700_003_600_000
            ),
        ] },
        fetchMarginAccount: {
            BinanceMarginAccount(
                marginLevel: "1.5",
                totalAssetOfBtc: "0.5",
                totalLiabilityOfBtc: "0.1",
                totalNetAssetOfBtc: "0.4",
                totalAsset: "32500",
                totalLiability: "6500",
                totalNetAsset: "26000",
                maxBorrowable: "13000",
                maintained: "1000",
                userAssets: [
                    BinanceMarginAccount.AssetEntry(
                        asset: "BTC", borrowed: "0", free: "0.5",
                        locked: "0", interest: "0", netAsset: "0.5",
                        netAssetOfBtc: "0.5", maxBorrowable: "0.5"
                    ),
                ]
            )
        },
        fetchIsolatedMarginAccount: { _ in
            BinanceIsolatedMarginAccount(
                assets: [
                    BinanceIsolatedMarginAccount.IsolatedPair(
                        symbol: "BTCUSDT",
                        marginLevel: "3.5",
                        marginRatio: "0.15",
                        indexPrice: "65000",
                        liquidatePrice: "45230",
                        liquidateRate: "1.0",
                        tradeEnabled: true,
                        enabled: true,
                        baseAsset: BinanceIsolatedMarginAccount.AssetDetail(
                            asset: "BTC", borrowed: "0.1", free: "0.5",
                            locked: "0", interest: "0.001", netAsset: "0.4"
                        ),
                        quoteAsset: BinanceIsolatedMarginAccount.AssetDetail(
                            asset: "USDT", borrowed: "0", free: "1000",
                            locked: "0", interest: "0", netAsset: "1000"
                        )
                    ),
                ],
                totalAssetOfBtc: "0.9",
                totalLiabilityOfBtc: "0.1",
                totalNetAssetOfBtc: "0.8"
            )
        },
        fetchMarginMyTrades: { _, _, _ in [
            BinanceMarginTrade(
                id: 1, symbol: "BTCUSDT", price: "50000", qty: "0.5",
                quoteQty: "25000", commission: "0.001", commissionAsset: "BTC",
                time: 1_700_000_000_000, isBuyer: true, orderId: 100,
                isIsolated: false, marginBuyBorrowAmount: nil, marginBuyBorrowAsset: nil
            ),
        ] },
        fetchMarginOpenOrders: { _, _ in [] },
        fetchMarginAllAssets: {
            [
                BinanceMarginAsset(
                    asset: "BTC", borrowed: "0", free: "0.5",
                    locked: "0", netAsset: "0.5", maxBorrowable: "0.5", maintained: nil
                ),
            ]
        },
        fetchIsolatedMarginTransfers: { _ in [
            BinanceMarginTransfer(
                asset: "USDT", symbol: "BTCUSDT", transferType: "1",
                amount: "1000", timestamp: 1_700_000_000_000,
                status: "SUCCESS", tranId: 1
            ),
        ] }
    )

    static let noop = BinanceAPIClient(
        fetchAccount: { [] },
        fetchMyTrades: { _, _ in [] },
        fetchTickerPrices: { _ in [] },
        fetchKlines: { _, _, _ in [] },
        fetchMarginAccount: {
            BinanceMarginAccount(
                marginLevel: "0",
                totalAssetOfBtc: "0",
                totalLiabilityOfBtc: "0",
                totalNetAssetOfBtc: "0",
                totalAsset: "0",
                totalLiability: "0",
                totalNetAsset: "0",
                maxBorrowable: "0",
                maintained: nil,
                userAssets: []
            )
        },
        fetchIsolatedMarginAccount: { _ in .empty },
        fetchMarginMyTrades: { _, _, _ in [] },
        fetchMarginOpenOrders: { _, _ in [] },
        fetchMarginAllAssets: { [] },
        fetchIsolatedMarginTransfers: { _ in [] }
    )
}

// MARK: - Debug Logging

nonisolated enum BinanceDebugLogger {
    static func logJSONResponse(_ data: Data, endpoint: String, logger: Logger) {
        guard let prettyJSON = prettyPrintedJSONString(from: data) else {
            logger.debug("Binance \(endpoint) response: \(String(decoding: data, as: UTF8.self), privacy: .public)")
            return
        }

        logger.debug("Binance \(endpoint) response:\n\(prettyJSON, privacy: .public)")
    }

    private static func prettyPrintedJSONString(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }

        return prettyString
    }
}
