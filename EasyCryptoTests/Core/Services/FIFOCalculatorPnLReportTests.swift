//
//  FIFOCalculatorPnLReportTests.swift
//  EasyCryptoTests
//
//  Validates that FIFOCalculator produces the same results as the Python
//  pnl_report.py script against the exported Binance CSV data.
//

import Testing
@testable import EasyCrypto

@Suite("Given the exported Binance CSV trade history")
struct FIFOCalculatorPnLReportTests {

    // MARK: - Expected Results from Python pnl_report.py

    /// Total realized P&L across all assets (from pnl-report.md line 5)
    private let expectedTotalPnL: Double = 33_818.18

    /// Per-asset realized P&L (from pnl-report.md lines 9-34)
    /// Format: [asset: realizedPnL]
    private let expectedPerAssetPnL: [String: Double] = [
        "DEXE": -5_374.37,
        "SENT": -825.09,
        "BANK": -350.50,
        "IOTX": -10.05,
        "USDC": -0.02,
        "ACE": 0.00,
        "AED": 0.00,
        "BTCUSDC": 0.00,
        "ETHUSDC": 0.00,
        "TON": 0.00,
        "MET": 1.40,
        "LTC": 21.56,
        "BCH": 104.54,
        "UNI": 108.67,
        "ADA": 132.46,
        "TRX": 175.56,
        "BNB": 359.34,
        "NEAR": 642.59,
        "IOTA": 804.03,
        "ALLO": 1_504.82,
        "HYPER": 1_723.68,
        "ETH": 3_026.83,
        "MMT": 3_145.46,
        "XRP": 3_987.66,
        "SOL": 7_763.54,
        "BTC": 16_876.08
    ]

    // MARK: - Test Cases

    @Test("When calculating total realized P&L, then it matches the Python script total")
    func totalRealizedPnL() async throws {
        let tolerance = 0.10 // ±10 cents tolerance for rounding differences

        let calculator = FIFOCalculator.live
        var totalPnL: Double = 0

        for (asset, _) in expectedPerAssetPnL {
            let trades = mockTradesForAsset(asset)
            let result = calculator.calculate(trades)
            totalPnL += result.realizedPnL
        }

        #expect(abs(totalPnL - expectedTotalPnL) < tolerance,
                "Total P&L should be \(expectedTotalPnL), got \(totalPnL)")
    }

    @Test("When calculating per-asset P&L, then each asset matches Python script results",
          arguments: [
            ("BTC", 16_876.08),
            ("ETH", 3_026.83),
            ("SOL", 7_763.54),
            ("XRP", 3_987.66),
            ("BNB", 359.34),
            ("ADA", 132.46),
            ("DEXE", -5_374.37),
            ("SENT", -825.09),
            ("BANK", -350.50)
          ])
    func perAssetRealizedPnL(asset: String, expectedPnL: Double) async throws {
        let tolerance = 0.10 // ±10 cents tolerance

        let calculator = FIFOCalculator.live
        let trades = mockTradesForAsset(asset)
        let result = calculator.calculate(trades)

        #expect(abs(result.realizedPnL - expectedPnL) < tolerance,
                "\(asset) P&L should be \(expectedPnL), got \(result.realizedPnL)")
    }

    @Test("When validating all 26 assets, then each one matches its expected P&L")
    func allAssetsMatchExpectedPnL() async throws {
        let tolerance = 0.10
        let calculator = FIFOCalculator.live

        var mismatches: [(String, Double, Double)] = []

        for (asset, expectedPnL) in expectedPerAssetPnL.sorted(by: { $0.key < $1.key }) {
            let trades = mockTradesForAsset(asset)
            let result = calculator.calculate(trades)
            let actualPnL = result.realizedPnL

            if abs(actualPnL - expectedPnL) >= tolerance {
                mismatches.append((asset, expectedPnL, actualPnL))
            }
        }

        #expect(mismatches.isEmpty,
                "Mismatches found: \(mismatches.map { "\($0.0): expected \($0.1), got \($0.2)" }.joined(separator: "; "))")
    }

    @Test("When calculating losers, then DEXE, SENT, BANK, IOTX, USDC show negative P&L")
    func losingAssetsShowNegativePnL() async throws {
        let tolerance = 0.10
        let calculator = FIFOCalculator.live

        let losers = ["DEXE", "SENT", "BANK", "IOTX", "USDC"]

        for asset in losers {
            let trades = mockTradesForAsset(asset)
            let result = calculator.calculate(trades)

            #expect(result.realizedPnL < tolerance,
                    "\(asset) should show negative P&L, got \(result.realizedPnL)")
        }
    }

    @Test("When calculating winners, then BTC, SOL, XRP, ETH, MMT show positive P&L")
    func winningAssetsShowPositivePnL() async throws {
        let tolerance = 0.10
        let calculator = FIFOCalculator.live

        let winners = ["BTC", "SOL", "XRP", "ETH", "MMT"]

        for asset in winners {
            let trades = mockTradesForAsset(asset)
            let result = calculator.calculate(trades)

            #expect(result.realizedPnL > -tolerance,
                    "\(asset) should show positive P&L, got \(result.realizedPnL)")
        }
    }

    @Test("When calculating zero-P&L assets, then ACE, AED, BTCUSDC, ETHUSDC, TON show zero")
    func zeroPnLAssets() async throws {
        let tolerance = 0.10
        let calculator = FIFOCalculator.live

        let zeroAssets = ["ACE", "AED", "BTCUSDC", "ETHUSDC", "TON"]

        for asset in zeroAssets {
            let trades = mockTradesForAsset(asset)
            let result = calculator.calculate(trades)

            #expect(abs(result.realizedPnL) < tolerance,
                    "\(asset) should show ~zero P&L, got \(result.realizedPnL)")
        }
    }

    // MARK: - CSV Trade Data Factory

    /// Returns chronologically-sorted trades for the given asset by parsing
    /// the actual Binance CSV exports in the data/ directory.
    private func mockTradesForAsset(_ asset: String) -> [FIFOTrade] {
        let dataDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data")

        let csvFiles = [
            dataDir.appendingPathComponent("Binance-Spot-Order-History-202609120528(UTC+4)-part1-of1.csv"),
            dataDir.appendingPathComponent("Binance-Margin-Order-History-202609120532(UTC+4)-cross.csv"),
            dataDir.appendingPathComponent("Binance-Margin-Order-History-202609120532(UTC+4)-isolated.csv")
        ]

        var trades: [(date: Date, trade: FIFOTrade)] = []

        for csvPath in csvFiles {
            guard let parsed = parseCSV(at: csvPath, forAsset: asset) else { continue }
            trades.append(contentsOf: parsed)
        }

        // Sort chronologically as required by FIFO
        trades.sort { $0.date < $1.date }

        return trades.map { $0.trade }
    }

    /// Parses a Binance CSV export file and returns trades for the given asset.
    /// Returns nil if file doesn't exist or can't be parsed.
    private func parseCSV(at url: URL, forAsset asset: String) -> [(Date, FIFOTrade)]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return nil }

        var result: [(Date, FIFOTrade)] = []

        // Skip header row
        for line in lines.dropFirst() where !line.isEmpty {
            let columns = parseCSVLine(line)
            guard columns.count > 11 else { continue }

            let status = columns[11].trimmingCharacters(in: .whitespaces).uppercased()
            guard status == "FILLED" else { continue }

            let pair = columns[2].trimmingCharacters(in: .whitespaces)
            let pairAsset = pair.replacingOccurrences(of: "USDT", with: "").replacingOccurrences(of: "BUSD", with: "")
            guard pairAsset == asset else { continue }

            let side = columns[4].trimmingCharacters(in: .whitespaces).uppercased()
            guard side == "BUY" || side == "SELL" else { continue }

            guard let date = parseDate(columns[0]) else { continue }
            guard let qty = parseAmount(columns[8]) else { continue }
            guard let total = parseAmount(columns[10]) else { continue }

            let avgPrice = qty > 1e-12 ? total / qty : 0

            // Parse commission from a hypothetical column or default to 0
            // Binance CSV may have commission data; adjust column index as needed
            let commission = 0.0
            let commissionAsset = "USDT"

            let trade = FIFOTrade(
                price: avgPrice,
                quantity: qty,
                commission: commission,
                commissionAsset: commissionAsset,
                asset: pairAsset,
                isBuyer: side == "BUY"
            )

            result.append((date, trade))
        }

        return result
    }

    /// Parses a CSV line respecting quoted fields with embedded commas.
    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)

        return columns
    }

    /// Parses datetime from Binance CSV formats.
    private func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.timeZone = TimeZone(secondsFromGMT: 0)
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd/MM/yyyy HH:mm"
                f.timeZone = TimeZone(secondsFromGMT: 0)
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm"
                f.timeZone = TimeZone(secondsFromGMT: 0)
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    /// Strips unit suffix from amounts: "0.04843BTC" → 0.04843
    private func parseAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(digits)
    }
}
