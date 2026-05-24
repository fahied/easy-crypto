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
        BinanceAPIClient(
            fetchAccount: {
                guard let credentials = try keychain.load() else {
                    throw BinanceError.noCredentialsConfigured
                }
                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
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
                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
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
        ] }
    )

    static let noop = BinanceAPIClient(
        fetchAccount: { [] },
        fetchMyTrades: { _, _ in [] },
        fetchTickerPrices: { _ in [] },
        fetchKlines: { _, _, _ in [] }
    )
}
