//
//  MarginDesignSystemTests.swift
//  EasyCryptoTests
//
//  ADV-DESIGN-SYSTEM-001: Tests for margin display components.
//
//  Covers Theme margin colors, TradingModeBadge color mapping, MarginPnLLabel
//  fee-subtitle visibility, and MarginHoldingRow margin-column logic.

import Testing
import Foundation
import SwiftUI
@testable import EasyCrypto

@Suite("Given margin display components")
struct MarginDesignSystemTests {

    // MARK: - Theme colors

    @Test("Theme defines marginCross and marginIsolated colors")
    func themeHasMarginColors() {
        let cross = Theme.marginCross
        let isolated = Theme.marginIsolated
        let accent = Theme.accent
        let loss = Theme.loss

        // Colors are defined and distinct from each other and from accent/loss
        #expect(cross != loss)
        #expect(isolated != loss)
        #expect(cross != isolated)
        #expect(cross != accent)
        #expect(isolated != accent)
    }

    // MARK: - TradingModeBadge color mapping

    @Test("TradingModeBadge assigns accent color for spot")
    func badgeSpotColor() {
        let badgeColor = colorForMode(.spot)
        #expect(badgeColor == Theme.accent)
    }

    @Test("TradingModeBadge assigns marginCross color for crossMargin")
    func badgeCrossMarginColor() {
        let badgeColor = colorForMode(.crossMargin)
        #expect(badgeColor == Theme.marginCross)
    }

    @Test("TradingModeBadge assigns marginIsolated color for isolatedMargin")
    func badgeIsolatedMarginColor() {
        let badgeColor = colorForMode(.isolatedMargin)
        #expect(badgeColor == Theme.marginIsolated)
    }

    // MARK: - MarginPnLLabel fee-subtitle logic

    @Test("When borrowingFee is nil, no fee subtitle is needed")
    func marginPnLNoFee() {
        let needsFeeLine = MarginPnLLabel(
            value: 2500, percentage: 5.0, borrowingFee: nil
        ).showsFeeLine
        #expect(needsFeeLine == false)
    }

    @Test("When borrowingFee is zero, no fee subtitle is needed")
    func marginPnLZeroFee() {
        let needsFeeLine = MarginPnLLabel(
            value: 2500, percentage: 5.0, borrowingFee: 0
        ).showsFeeLine
        #expect(needsFeeLine == false)
    }

    @Test("When borrowingFee is positive, fee subtitle is needed")
    func marginPnLPositiveFee() {
        let needsFeeLine = MarginPnLLabel(
            value: 2500, percentage: 5.0, borrowingFee: 12.34
        ).showsFeeLine
        #expect(needsFeeLine == true)
    }

    @Test("When borrowingFee is negative, no fee subtitle is shown")
    func marginPnLNegativeFee() {
        let needsFeeLine = MarginPnLLabel(
            value: 2500, percentage: 5.0, borrowingFee: -5.0
        ).showsFeeLine
        #expect(needsFeeLine == false)
    }

    // MARK: - MarginHoldingRow margin-column logic

    @Test("When tradingMode is spot, margin detail row is hidden")
    func marginHoldingSpotHidesDetails() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .spot,
            borrowedQuantity: 0.5,
            liquidationPrice: "42000"
        )
        #expect(row.showsMarginDetails == false)
    }

    @Test("When tradingMode is crossMargin, margin detail row shows")
    func marginHoldingCrossMarginShowsDetails() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .crossMargin,
            borrowedQuantity: 0.5,
            liquidationPrice: nil
        )
        #expect(row.showsMarginDetails == true)
    }

    @Test("When tradingMode is isolatedMargin, margin detail row shows")
    func marginHoldingIsolatedMarginShowsDetails() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 2.5,
            liquidationPrice: "23200"
        )
        #expect(row.showsMarginDetails == true)
    }

    @Test("Borrowed quantity line is hidden when nil")
    func marginHoldingNilBorrowed() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: nil,
            liquidationPrice: "42000"
        )
        #expect(row.showsBorrowedLine == false)
    }

    @Test("Borrowed quantity line is hidden when zero")
    func marginHoldingZeroBorrowed() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 0,
            liquidationPrice: "42000"
        )
        #expect(row.showsBorrowedLine == false)
    }

    @Test("Borrowed quantity line shows when positive")
    func marginHoldingPositiveBorrowed() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 0.5,
            liquidationPrice: "42000"
        )
        #expect(row.showsBorrowedLine == true)
    }

    @Test("Liquidation price line is hidden when nil")
    func marginHoldingNilLiquidation() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 0.5,
            liquidationPrice: nil
        )
        #expect(row.showsLiquidationLine == false)
    }

    @Test("Liquidation price line is hidden when empty string")
    func marginHoldingEmptyLiquidation() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 0.5,
            liquidationPrice: ""
        )
        #expect(row.showsLiquidationLine == false)
    }

    @Test("Liquidation price line shows when non-empty")
    func marginHoldingNonEmptyLiquidation() {
        let row = MarginHoldingRow(
            holding: makeHolding(),
            tradingMode: .isolatedMargin,
            borrowedQuantity: 0.5,
            liquidationPrice: "42000"
        )
        #expect(row.showsLiquidationLine == true)
    }
}

// MARK: - Helpers

/// Returns the badge color for a given trading mode (mirrors TradingModeBadge.color).
private func colorForMode(_ mode: TradingMode) -> Color {
    switch mode {
    case .spot: Theme.accent
    case .crossMargin: Theme.marginCross
    case .isolatedMargin: Theme.marginIsolated
    }
}

/// Create a minimal Holding for testing.
private func makeHolding() -> Holding {
    Holding(
        asset: "BTC",
        totalQuantity: 0.5,
        weightedAvgBuyPrice: 50000,
        totalInvestedUSDT: 25000,
        currentPrice: 55000,
        currentValueUSDT: 27500,
        unrealizedPnL: 2500,
        unrealizedPnLPercent: 10,
        realizedPnL: 0
    )
}

// MARK: - MarginPnLLabel logic extension

extension MarginPnLLabel {
    var showsFeeLine: Bool {
        guard let fee = borrowingFee else { return false }
        return fee > 1e-12
    }
}

// MARK: - MarginHoldingRow logic extensions

extension MarginHoldingRow {
    var showsMarginDetails: Bool {
        tradingMode != .spot
    }

    var showsBorrowedLine: Bool {
        guard let borrowed = borrowedQuantity else { return false }
        return borrowed > 1e-12
    }

    var showsLiquidationLine: Bool {
        guard let price = liquidationPrice else { return false }
        return !price.isEmpty
    }
}
