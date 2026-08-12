//
//  MarginHoldingRow.swift
//  EasyCrypto
//
//  Holding row with margin-specific columns: borrowed quantity and liquidation price.
//  Used in the Holdings tab, where the mode picker already identifies the trading mode.
//  Falls back to standard holding display for spot.
//
//  Margin-specific fields (borrowed quantity, liquidation price) are passed as
//  optional parameters — ADV-PORTFOLIO-002 wires them from IsolatedMarginBalance.

import SwiftUI

struct MarginHoldingRow: View {
    let holding: Holding
    let tradingMode: TradingMode
    let borrowedQuantity: Double?
    let liquidationPrice: String?

    private var hasCostBasis: Bool { holding.weightedAvgBuyPrice > 0 }
    private var isFlat: Bool { abs(holding.unrealizedPnL) < 0.005 }
    private var isUp: Bool { holding.unrealizedPnL >= 0 }
    private var pnlColor: Color { isFlat ? Theme.neutral : (isUp ? Theme.profit : Theme.loss) }

    private var marketColor: Color {
        guard hasCostBasis, holding.currentPrice > 0 else { return .primary }
        if holding.currentPrice > holding.weightedAvgBuyPrice { return Theme.profit }
        if holding.currentPrice < holding.weightedAvgBuyPrice { return Theme.loss }
        return .primary
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            statsStrip
        }
        .glassCard(cornerRadius: Theme.smallRadius + 4, padding: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.asset)
                    .font(.subheadline.weight(.semibold))
                Text(holding.totalQuantity.quantityFormatted)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(holding.currentValueUSDT.usdtFormatted)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()

                pnlPill
            }
        }
    }

    private var pnlPill: some View {
        HStack(spacing: 3) {
            if !isFlat {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(holding.unrealizedPnL.signedUsdtFormatted)
                .monospacedDigit()
            Text(holding.unrealizedPnLPercent.percentFormatted)
                .monospacedDigit()
                .foregroundStyle(pnlColor.opacity(0.75))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(pnlColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(pnlColor.opacity(0.14))
        }
    }

    // MARK: - Stats

    private var statsStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            stat(
                label: "Avg Buy",
                value: hasCostBasis ? holding.weightedAvgBuyPrice.priceFormatted : "\u{2014}"
            )
            stat(
                label: "Market",
                value: holding.currentPrice > 0 ? holding.currentPrice.priceFormatted : "\u{2014}",
                tint: marketColor
            )

            if tradingMode != .spot {
                if let borrowed = borrowedQuantity, borrowed > 1e-12 {
                    stat(label: "Borrowed", value: borrowed.quantityFormatted, tint: Theme.loss)
                }
                if let liqPrice = liquidationPrice, !liqPrice.isEmpty {
                    stat(label: "Liq. Price", value: "$\(liqPrice)", tint: Theme.loss)
                }
            }
        }
    }

    private func stat(label: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Cross Margin") {
    MarginHoldingRow(
        holding: Holding(
            asset: "BTC", totalQuantity: 0.5, weightedAvgBuyPrice: 50000,
            totalInvestedUSDT: 25000, currentPrice: 55000,
            currentValueUSDT: 27500, unrealizedPnL: 2500,
            unrealizedPnLPercent: 10, realizedPnL: 0
        ),
        tradingMode: .crossMargin,
        borrowedQuantity: 0.3,
        liquidationPrice: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Isolated Margin") {
    MarginHoldingRow(
        holding: Holding(
            asset: "ETH", totalQuantity: 5.0, weightedAvgBuyPrice: 3000,
            totalInvestedUSDT: 15000, currentPrice: 3500,
            currentValueUSDT: 17500, unrealizedPnL: 5000,
            unrealizedPnLPercent: 33.33, realizedPnL: 1200
        ),
        tradingMode: .isolatedMargin,
        borrowedQuantity: 2.5,
        liquidationPrice: "2320"
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Spot") {
    MarginHoldingRow(
        holding: Holding(
            asset: "SOL", totalQuantity: 100, weightedAvgBuyPrice: 150,
            totalInvestedUSDT: 15000, currentPrice: 175,
            currentValueUSDT: 17500, unrealizedPnL: 2500,
            unrealizedPnLPercent: 16.67, realizedPnL: 0
        ),
        tradingMode: .spot,
        borrowedQuantity: nil,
        liquidationPrice: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}
