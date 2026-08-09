//
//  MarginHoldingRow.swift
//  EasyCrypto
//
//  Holding row with margin-specific columns: trading mode badge, borrowed quantity,
//  and liquidation price. Used in the Portfolio Holdings tab when trading mode is
//  cross-margin or isolated-margin. Falls back to standard holding display for spot.
//
//  Margin-specific fields (borrowed quantity, liquidation price) are passed as
//  optional parameters — ADV-PORTFOLIO-002 wires them from IsolatedMarginBalance.

import SwiftUI

struct MarginHoldingRow: View {
    let holding: Holding
    let tradingMode: TradingMode
    let borrowedQuantity: Double?
    let liquidationPrice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main row: asset info + value + P&L
            HStack(spacing: 12) {
                // Asset icon placeholder
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(holding.asset.prefix(1)))
                            .font(.headline.bold())
                            .foregroundStyle(Theme.accent)
                    }

                // Asset info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(holding.asset)
                            .font(.headline)
                        TradingModeBadge(mode: tradingMode)
                    }
                    Text("\(holding.totalQuantity.quantityFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Value & P&L
                VStack(alignment: .trailing, spacing: 2) {
                    Text(holding.currentValueUSDT.usdtFormatted)
                        .font(.headline)
                    MarginPnLLabel(
                        value: holding.unrealizedPnL,
                        percentage: holding.unrealizedPnLPercent,
                        borrowingFee: nil, // caller can pass when available
                        font: .caption.bold()
                    )
                }
            }

            // Margin-specific detail row (hidden for spot)
            if tradingMode != .spot {
                HStack(spacing: 16) {
                    if let borrowed = borrowedQuantity, borrowed > 1e-12 {
                        HStack(spacing: 4) {
                            Text("Borrowed:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(borrowed.quantityFormatted)")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.loss)
                        }
                    }

                    if let liqPrice = liquidationPrice, !liqPrice.isEmpty {
                        HStack(spacing: 4) {
                            Text("Liq:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(liqPrice)")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.loss)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .glassCard()
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
