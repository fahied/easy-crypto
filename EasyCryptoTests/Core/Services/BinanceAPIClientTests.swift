//
//  BinanceAPIClientTests.swift
//  EasyCryptoTests
//

import Foundation
import Testing

@testable import EasyCrypto

// MARK: - HMAC Signing Tests

@Suite("Given HMAC-SHA256 signing parameters")
struct HMACSigningTests {

    @Test("When signing a known query string, then produces a 64-character hex signature")
    func producesValidHexSignature() {
        let signature = BinanceSigner.sign(
            queryString: "symbol=BTCUSDT&timestamp=1234567890",
            secret: "testSecret123"
        )
        #expect(signature.count == 64)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }

    @Test("When signing the same input twice, then produces identical signatures")
    func deterministicSignature() {
        let input = "symbol=BTCUSDT&timestamp=1234567890"
        let secret = "mySecret"
        let sig1 = BinanceSigner.sign(queryString: input, secret: secret)
        let sig2 = BinanceSigner.sign(queryString: input, secret: secret)
        #expect(sig1 == sig2)
    }

    @Test("When signing different query strings, then produces different signatures")
    func differentInputsDifferentSignatures() {
        let secret = "mySecret"
        let sig1 = BinanceSigner.sign(queryString: "a=1", secret: secret)
        let sig2 = BinanceSigner.sign(queryString: "a=2", secret: secret)
        #expect(sig1 != sig2)
    }

    @Test("When signing with different secrets, then produces different signatures")
    func differentSecretsDifferentSignatures() {
        let input = "symbol=BTCUSDT"
        let sig1 = BinanceSigner.sign(queryString: input, secret: "secret1")
        let sig2 = BinanceSigner.sign(queryString: input, secret: "secret2")
        #expect(sig1 != sig2)
    }

    @Test("When signing an empty query string, then still produces a valid 64-char hex")
    func emptyQueryString() {
        let signature = BinanceSigner.sign(queryString: "", secret: "secret")
        #expect(signature.count == 64)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }
}

// MARK: - URL Construction Tests

@Suite("Given Binance API URL construction")
struct URLConstructionTests {

    @Test("When building a signed URL, then includes timestamp and signature in query")
    func signedURLHasTimestampAndSignature() throws {
        let url = try #require(BinanceURLBuilder.buildSignedURL(
            path: "/api/v3/account",
            secret: "testSecret",
            timestamp: 1_700_000_000_000
        ))
        let query = try #require(url.query)
        #expect(query.contains("timestamp=1700000000000"))
        #expect(query.contains("signature="))
    }

    @Test("When building a signed URL with params, then all params appear in query")
    func signedURLIncludesAllParams() throws {
        let url = try #require(BinanceURLBuilder.buildSignedURL(
            path: "/api/v3/myTrades",
            params: [("symbol", "BTCUSDT"), ("limit", "1000")],
            secret: "testSecret",
            timestamp: 1_700_000_000_000
        ))
        let query = try #require(url.query)
        #expect(query.contains("symbol=BTCUSDT"))
        #expect(query.contains("limit=1000"))
        #expect(query.contains("timestamp="))
        #expect(query.contains("signature="))
    }

    @Test("When building a signed URL, then base URL is api.binance.com with HTTPS")
    func signedURLHasCorrectBase() throws {
        let url = try #require(BinanceURLBuilder.buildSignedURL(
            path: "/api/v3/account",
            secret: "s",
            timestamp: 0
        ))
        #expect(url.host == "api.binance.com")
        #expect(url.scheme == "https")
        #expect(url.path == "/api/v3/account")
    }

    @Test("When building a public URL with params, then includes params without signature")
    func publicURLWithParams() throws {
        let url = try #require(BinanceURLBuilder.buildPublicURL(
            path: "/api/v3/ticker/price",
            params: [("symbol", "BTCUSDT")]
        ))
        let query = try #require(url.query)
        #expect(query.contains("symbol=BTCUSDT"))
        #expect(!query.contains("signature="))
        #expect(!query.contains("timestamp="))
    }

    @Test("When building a public URL without params, then has no query string")
    func publicURLNoParams() throws {
        let url = try #require(BinanceURLBuilder.buildPublicURL(
            path: "/api/v3/ticker/price"
        ))
        #expect(url.query == nil)
    }
}

// MARK: - Response Mapping Tests

@Suite("Given a Binance API HTTP response")
struct ResponseMappingTests {

    private func makeHTTPResponse(
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.binance.com/api/v3/test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    @Test("When status is 200, then returns the response data unchanged")
    func successReturnsData() throws {
        let body = Data("OK".utf8)
        let response = makeHTTPResponse(statusCode: 200)
        let result = try BinanceResponseMapper.mapResponse(data: body, response: response)
        #expect(result == body)
    }

    @Test("When status is 401, then throws invalidCredentials")
    func unauthorizedThrowsInvalidCredentials() throws {
        let response = makeHTTPResponse(statusCode: 401)
        do {
            _ = try BinanceResponseMapper.mapResponse(data: Data(), response: response)
            Issue.record("Expected BinanceError.invalidCredentials")
        } catch {
            guard case BinanceError.invalidCredentials = error else {
                Issue.record("Expected invalidCredentials, got \(error)")
                return
            }
        }
    }

    @Test("When status is 403, then throws invalidCredentials")
    func forbiddenThrowsInvalidCredentials() throws {
        let response = makeHTTPResponse(statusCode: 403)
        do {
            _ = try BinanceResponseMapper.mapResponse(data: Data(), response: response)
            Issue.record("Expected BinanceError.invalidCredentials")
        } catch {
            guard case BinanceError.invalidCredentials = error else {
                Issue.record("Expected invalidCredentials, got \(error)")
                return
            }
        }
    }

    @Test("When status is 429, then throws rateLimited")
    func rateLimitedThrows() throws {
        let response = makeHTTPResponse(statusCode: 429)
        do {
            _ = try BinanceResponseMapper.mapResponse(data: Data(), response: response)
            Issue.record("Expected BinanceError.rateLimited")
        } catch {
            guard case BinanceError.rateLimited = error else {
                Issue.record("Expected rateLimited, got \(error)")
                return
            }
        }
    }

    @Test("When status is 429 with Retry-After header, then includes retry seconds")
    func rateLimitedWithRetryAfter() throws {
        let response = makeHTTPResponse(statusCode: 429, headers: ["Retry-After": "30"])
        do {
            _ = try BinanceResponseMapper.mapResponse(data: Data(), response: response)
            Issue.record("Expected BinanceError.rateLimited")
        } catch {
            guard case BinanceError.rateLimited(let retryAfter) = error else {
                Issue.record("Expected rateLimited, got \(error)")
                return
            }
            #expect(retryAfter == 30)
        }
    }

    @Test("When status is 400 with API error JSON, then throws apiError with code and message")
    func apiErrorWithJSON() throws {
        let json = #"{"code":-1100,"msg":"Illegal characters found"}"#
        let data = Data(json.utf8)
        let response = makeHTTPResponse(statusCode: 400)
        do {
            _ = try BinanceResponseMapper.mapResponse(data: data, response: response)
            Issue.record("Expected BinanceError.apiError")
        } catch {
            guard case BinanceError.apiError(let code, let message) = error else {
                Issue.record("Expected apiError, got \(error)")
                return
            }
            #expect(code == -1100)
            #expect(message == "Illegal characters found")
        }
    }

    @Test("When status is 500 with no valid JSON, then throws apiError with status code")
    func serverErrorFallback() throws {
        let response = makeHTTPResponse(statusCode: 500)
        do {
            _ = try BinanceResponseMapper.mapResponse(data: Data("bad".utf8), response: response)
            Issue.record("Expected BinanceError.apiError")
        } catch {
            guard case BinanceError.apiError(let code, let message) = error else {
                Issue.record("Expected apiError, got \(error)")
                return
            }
            #expect(code == 500)
            #expect(message == "Unknown error")
        }
    }
}

// MARK: - DTO Decoding Tests

@Suite("Given Binance API response JSON")
struct ResponseDecodingTests {

    @Test("When decoding account response, then maps balances with all fields")
    func decodeAccountResponse() throws {
        let json = """
        {"balances":[{"asset":"BTC","free":"0.50000000","locked":"0.00000000"},\
        {"asset":"ETH","free":"10.00000000","locked":"1.00000000"}]}
        """
        let response = try JSONDecoder().decode(
            BinanceAccountResponse.self,
            from: Data(json.utf8)
        )
        #expect(response.balances.count == 2)
        #expect(response.balances[0].asset == "BTC")
        #expect(response.balances[0].free == "0.50000000")
        #expect(response.balances[0].locked == "0.00000000")
        #expect(response.balances[1].asset == "ETH")
        #expect(response.balances[1].locked == "1.00000000")
    }

    @Test("When decoding trades, then maps all fields including isBuyer")
    func decodeTrades() throws {
        let json = """
        [{"id":28457,"symbol":"BTCUSDT","price":"4000.00000000",\
        "qty":"12.00000000","quoteQty":"48000.00000000",\
        "commission":"10.10000000","commissionAsset":"BTC",\
        "time":1499865549590,"isBuyer":true,"orderId":100234}]
        """
        let trades = try JSONDecoder().decode([BinanceTrade].self, from: Data(json.utf8))
        #expect(trades.count == 1)
        let trade = trades[0]
        #expect(trade.id == 28457)
        #expect(trade.symbol == "BTCUSDT")
        #expect(trade.price == "4000.00000000")
        #expect(trade.qty == "12.00000000")
        #expect(trade.quoteQty == "48000.00000000")
        #expect(trade.commission == "10.10000000")
        #expect(trade.commissionAsset == "BTC")
        #expect(trade.time == 1_499_865_549_590)
        #expect(trade.isBuyer == true)
        #expect(trade.orderId == 100234)
    }

    @Test("When decoding ticker prices array, then maps symbol and price")
    func decodeTickerPricesArray() throws {
        let json = """
        [{"symbol":"BTCUSDT","price":"65000.12"},\
        {"symbol":"ETHUSDT","price":"3500.99"}]
        """
        let prices = try JSONDecoder().decode(
            [BinanceTickerPrice].self,
            from: Data(json.utf8)
        )
        #expect(prices.count == 2)
        #expect(prices[0].symbol == "BTCUSDT")
        #expect(prices[0].price == "65000.12")
        #expect(prices[1].symbol == "ETHUSDT")
    }

    @Test("When decoding a single ticker price, then maps correctly")
    func decodeSingleTickerPrice() throws {
        let json = #"{"symbol":"BTCUSDT","price":"65000.12"}"#
        let price = try JSONDecoder().decode(
            BinanceTickerPrice.self,
            from: Data(json.utf8)
        )
        #expect(price.symbol == "BTCUSDT")
        #expect(price.price == "65000.12")
    }

    @Test("When decoding klines from Binance array format, then maps all numeric fields")
    func decodeKlines() throws {
        let json = """
        [[1499040000000,"0.01634000","0.80000000","0.01575800",\
        "0.01577100","148976.11427815",1499644799999,\
        "2434.19055334",308,"1756.87402397","28.46694368","0"]]
        """
        let klines = try JSONDecoder().decode(
            [BinanceKline].self,
            from: Data(json.utf8)
        )
        #expect(klines.count == 1)
        let k = klines[0]
        #expect(k.openTime == 1_499_040_000_000)
        #expect(k.open == 0.01634)
        #expect(k.high == 0.8)
        #expect(k.low == 0.015758)
        #expect(k.close == 0.015771)
        #expect(k.volume == 148_976.11427815)
        #expect(k.closeTime == 1_499_644_799_999)
    }

    @Test("When BinanceKline converts to Kline, then all fields transfer correctly")
    func binanceKlineToKline() throws {
        let json = """
        [[1700000000000,"50000.00","51000.00","49000.00",\
        "50500.00","1000.00",1700003600000]]
        """
        let bKlines = try JSONDecoder().decode(
            [BinanceKline].self,
            from: Data(json.utf8)
        )
        let kline = bKlines[0].toKline
        #expect(kline.openTime == 1_700_000_000_000)
        #expect(kline.open == 50000)
        #expect(kline.high == 51000)
        #expect(kline.close == 50500)
        #expect(kline.closeTime == 1_700_003_600_000)
    }

    @Test("When decoding API error response, then maps code and msg")
    func decodeAPIError() throws {
        let json = #"{"code":-1121,"msg":"Invalid symbol."}"#
        let error = try JSONDecoder().decode(
            BinanceAPIErrorResponse.self,
            from: Data(json.utf8)
        )
        #expect(error.code == -1121)
        #expect(error.msg == "Invalid symbol.")
    }
}

// MARK: - Error Description Tests

@Suite("Given a BinanceError")
struct BinanceErrorTests {

    @Test("When invalidCredentials, then provides clear description")
    func invalidCredentialsDescription() {
        let error = BinanceError.invalidCredentials
        #expect(error.errorDescription == "Invalid API credentials")
    }

    @Test("When rateLimited with retryAfter, then includes seconds in description")
    func rateLimitedWithRetry() {
        let error = BinanceError.rateLimited(retryAfterSeconds: 30)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("30"))
    }

    @Test("When rateLimited without retryAfter, then shows generic retry message")
    func rateLimitedNoRetry() {
        let error = BinanceError.rateLimited(retryAfterSeconds: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("try again"))
    }

    @Test("When apiError, then includes code and message in description")
    func apiErrorDescription() {
        let error = BinanceError.apiError(code: -1100, message: "Bad request")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("-1100"))
        #expect(desc.contains("Bad request"))
    }

    @Test("When noCredentialsConfigured, then mentions credentials")
    func noCredentialsDescription() {
        let error = BinanceError.noCredentialsConfigured
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("credentials"))
    }
}

// MARK: - Preview / Noop Client Tests

@Suite("Given a preview BinanceAPIClient")
struct PreviewClientTests {

    @Test("When calling fetchAccount, then returns non-empty sample balances")
    func previewFetchAccount() async throws {
        let balances = try await BinanceAPIClient.preview.fetchAccount()
        #expect(!balances.isEmpty)
        #expect(balances.contains { $0.asset == "BTC" })
    }

    @Test("When calling fetchMyTrades, then returns non-empty sample trades")
    func previewFetchMyTrades() async throws {
        let trades = try await BinanceAPIClient.preview.fetchMyTrades("BTCUSDT", nil)
        #expect(!trades.isEmpty)
        #expect(trades[0].symbol == "BTCUSDT")
    }

    @Test("When calling fetchTickerPrices, then returns non-empty sample prices")
    func previewFetchTickerPrices() async throws {
        let prices = try await BinanceAPIClient.preview.fetchTickerPrices(["BTCUSDT"])
        #expect(!prices.isEmpty)
    }

    @Test("When calling fetchKlines, then returns non-empty sample klines")
    func previewFetchKlines() async throws {
        let klines = try await BinanceAPIClient.preview.fetchKlines("BTCUSDT", "1d", 30)
        #expect(!klines.isEmpty)
    }

    @Test("When using noop client, then all endpoints return empty arrays")
    func noopReturnsEmpty() async throws {
        let client = BinanceAPIClient.noop
        #expect(try await client.fetchAccount().isEmpty)
        #expect(try await client.fetchMyTrades("BTCUSDT", nil).isEmpty)
        #expect(try await client.fetchTickerPrices(["BTCUSDT"]).isEmpty)
        #expect(try await client.fetchKlines("BTCUSDT", "1d", 30).isEmpty)
    }
}

// MARK: - URLProtocol Mock for Live Client Tests

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private let testCredentials = KeychainCredentials(apiKey: "testKey", secret: "testSecret")

private let testKeychain = KeychainService(
    save: { _, _ in },
    load: { testCredentials },
    delete: { }
)

private let emptyKeychain = KeychainService(
    save: { _, _ in },
    load: { nil },
    delete: { }
)

// MARK: - Live Client Integration Tests

@Suite("Given a live BinanceAPIClient with mocked network", .serialized)
struct LiveClientTests {

    @Test("When fetchAccount succeeds, then returns decoded balances")
    func fetchAccountSuccess() async throws {
        let json = #"{"balances":[{"asset":"BTC","free":"1.0","locked":"0"}]}"#
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v3/time" {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data(#"{"serverTime":1700000000000}"#.utf8))
            }
            #expect(request.value(forHTTPHeaderField: "X-MBX-APIKEY") == "testKey")
            #expect(request.url?.path == "/api/v3/account")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let balances = try await client.fetchAccount()
        #expect(balances.count == 1)
        #expect(balances[0].asset == "BTC")
    }

    @Test("When fetchAccount has no credentials, then throws noCredentialsConfigured")
    func fetchAccountNoCredentials() async {
        let client = BinanceAPIClient.live(keychain: emptyKeychain, session: makeMockSession())
        do {
            _ = try await client.fetchAccount()
            Issue.record("Expected noCredentialsConfigured")
        } catch {
            guard case BinanceError.noCredentialsConfigured = error else {
                Issue.record("Expected noCredentialsConfigured, got \(error)")
                return
            }
        }
    }

    @Test("When fetchAccount gets 401, then throws invalidCredentials")
    func fetchAccountUnauthorized() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        do {
            _ = try await client.fetchAccount()
            Issue.record("Expected invalidCredentials")
        } catch {
            guard case BinanceError.invalidCredentials = error else {
                Issue.record("Expected invalidCredentials, got \(error)")
                return
            }
        }
    }

    @Test("When fetchMyTrades succeeds, then returns decoded trades with correct params")
    func fetchMyTradesSuccess() async throws {
        let json = """
        [{"id":1,"symbol":"BTCUSDT","price":"50000","qty":"0.5",\
        "quoteQty":"25000","commission":"0.001","commissionAsset":"BTC",\
        "time":1700000000000,"isBuyer":true,"orderId":100}]
        """
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v3/time" {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data(#"{"serverTime":1700000000000}"#.utf8))
            }
            let query = request.url?.query ?? ""
            #expect(query.contains("symbol=BTCUSDT"))
            #expect(query.contains("limit=1000"))
            #expect(query.contains("fromId=500"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let trades = try await client.fetchMyTrades("BTCUSDT", 500)
        #expect(trades.count == 1)
        #expect(trades[0].symbol == "BTCUSDT")
    }

    @Test("When fetchMyTrades without fromId, then omits fromId param")
    func fetchMyTradesNoFromId() async throws {
        let json = "[]"
        MockURLProtocol.requestHandler = { request in
            let query = request.url?.query ?? ""
            #expect(!query.contains("fromId"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let trades = try await client.fetchMyTrades("BTCUSDT", nil)
        #expect(trades.isEmpty)
    }

    @Test("When fetchTickerPrices with single symbol, then returns single decoded price")
    func fetchTickerPricesSingle() async throws {
        let json = #"{"symbol":"BTCUSDT","price":"65000.00"}"#
        MockURLProtocol.requestHandler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("symbol=BTCUSDT"))
            #expect(!query.contains("symbols="))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let prices = try await client.fetchTickerPrices(["BTCUSDT"])
        #expect(prices.count == 1)
        #expect(prices[0].price == "65000.00")
    }

    @Test("When fetchTickerPrices with multiple symbols, then returns decoded array")
    func fetchTickerPricesMultiple() async throws {
        let json = #"[{"symbol":"BTCUSDT","price":"65000"},{"symbol":"ETHUSDT","price":"3500"}]"#
        MockURLProtocol.requestHandler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("symbols="))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let prices = try await client.fetchTickerPrices(["BTCUSDT", "ETHUSDT"])
        #expect(prices.count == 2)
    }

    @Test("When fetchKlines succeeds, then returns decoded Kline array")
    func fetchKlinesSuccess() async throws {
        let json = """
        [[1700000000000,"50000.00","51000.00","49000.00",\
        "50500.00","1000.00",1700003600000]]
        """
        MockURLProtocol.requestHandler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("symbol=BTCUSDT"))
            #expect(query.contains("interval=1d"))
            #expect(query.contains("limit=30"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        let klines = try await client.fetchKlines("BTCUSDT", "1d", 30)
        #expect(klines.count == 1)
        #expect(klines[0].open == 50000)
        #expect(klines[0].close == 50500)
    }

    @Test("When fetchAccount gets invalid JSON, then throws decodingError")
    func fetchAccountDecodingError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        do {
            _ = try await client.fetchAccount()
            Issue.record("Expected decodingError")
        } catch {
            guard case BinanceError.decodingError = error else {
                Issue.record("Expected decodingError, got \(error)")
                return
            }
        }
    }

    @Test("When fetchAccount builds request, then URL does not include omitZeroBalances")
    func fetchAccountDoesNotIncludeOmitZeroBalances() async throws {
        var capturedQuery: String?
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v3/time" {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data(#"{"serverTime":1700000000000}"#.utf8))
            }
            capturedQuery = request.url?.query
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"balances":[]}"#.utf8))
        }
        let client = BinanceAPIClient.live(keychain: testKeychain, session: makeMockSession())
        _ = try await client.fetchAccount()

        let query = try #require(capturedQuery)
        #expect(!query.contains("omitZeroBalances"),
            "fetchAccount should not include omitZeroBalances param")
    }
}
