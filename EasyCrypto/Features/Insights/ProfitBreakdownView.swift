//
//  ProfitBreakdownView.swift
//  EasyCrypto
//

import SwiftUI

/// A summary card showing per-asset realized P&L and the average profit per trade.
///
/// Data comes from a `TradeSummary` — no additional models or services are needed.
struct ProfitBreakdownView: View {
    let summary: TradeSummary

    private var sortedSymbols: [SymbolSummary] {
        summary.topSymbols.sorted { $0.realizedPnL > $1.realizedPnL }
    }

    private var averageProfitPerTrade: Double {
        guard summary.sellCount > 0 else { return 0 }
        return summary.totalRealizedPnL / Double(summary.sellCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profit Breakdown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if sortedSymbols.isEmpty {
                Text("No trades yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Per-asset rows
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedSymbols, id: \.symbol) { symbol in
                        HStack(spacing: 8) {
                            Text(symbol.asset)
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(symbol.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            PnLLabel(value: symbol.realizedPnL)
                                .font(.caption.bold())
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }

                Divider()

                // Average profit per trade
                HStack {
                    Text("Avg profit per trade")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    PnLLabel(value: averageProfitPerTrade)
                        .font(.subheadline.bold())
                }
                .padding(.top, 4)
            }
        }
        .padding(Theme.cardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Preview

#Preview("Profit breakdown — mixed P&L") {
    let summary = TradeSummary(
        totalTrades: 10,
        buyCount: 4,
        sellCount: 6,
        symbolCount: 3,
        totalRealizedPnL: 500,
        winningSells: 4,
        losingSells: 2,
        currentWinStreak: 0,
        currentLossStreak: 0,
        averageHoldingPeriodDays: 3.5,
        concentrationRatio: 0.4,
        topSymbols: [
            SymbolSummary(symbol: "BTCUSDT", asset: "BTC", tradeCount: 4, buyCount: 2, sellCount: 2, realizedPnL: 200),
            SymbolSummary(symbol: "ETHUSDT", asset: "ETH", tradeCount: 3, buyCount: 1, sellCount: 2, realizedPnL: 350),
            SymbolSummary(symbol: "SOLUSDT", asset: "SOL", tradeCount: 3, buyCount: 1, sellCount: 2, realizedPnL: -50),
        ]
    )

    ProfitBreakdownView(summary: summary)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Profit breakdown — empty") {
    ProfitBreakdownView(summary: .empty)
        .padding()
        .preferredColorScheme(.dark)
}
