//
//  DayDetailView.swift
//  EasyCrypto
//

import SwiftUI

struct DayDetailView: View {
    let date: Date
    let details: [DayTradeDetail]

    private var realizedPnL: Double {
        details.filter { !$0.isBuyer }.compactMap(\.realizedPnL).reduce(0, +)
    }

    private var buyCount: Int { details.filter(\.isBuyer).count }
    private var sellCount: Int { details.filter { !$0.isBuyer }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                summaryHeader
                transactionList
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(date.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            Text("Realized P&L")
                .font(.caption)
                .foregroundStyle(.secondary)

            PnLLabel(value: realizedPnL, showArrow: false, font: .largeTitle.bold())

            Text("\(buyCount) buy · \(sellCount) sell")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Transactions

    private var transactionList: some View {
        VStack(spacing: Theme.cardSpacing) {
            ForEach(details) { detail in
                TransactionBreakdownCard(detail: detail)
            }
        }
    }
}

// MARK: - Transaction Breakdown Card

private struct TransactionBreakdownCard: View {
    let detail: DayTradeDetail

    private var sideColor: Color {
        detail.isBuyer ? Theme.profit : Theme.loss
    }

    private var sideLabel: String {
        detail.isBuyer ? "BUY" : "SELL"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().opacity(0.2)
            metrics
        }
        .glassCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(sideLabel)
                .font(.caption.bold())
                .foregroundStyle(sideColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(sideColor.opacity(0.18))
                )

            Text(detail.asset)
                .font(.headline)

            Spacer()

            Text(detail.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metrics: some View {
        VStack(spacing: 8) {
            if detail.isBuyer {
                metricRow(label: "Buying price", value: detail.price.usdtFormatted)
                metricRow(label: "Quantity", value: detail.quantity.quantityFormatted)
                metricRow(label: "Total invested", value: detail.total.usdtFormatted)
            } else {
                metricRow(label: "Selling price", value: detail.price.usdtFormatted)
                if let costBasis = detail.costBasisPrice {
                    metricRow(label: "Buying price (avg)", value: costBasis.usdtFormatted)
                }
                metricRow(label: "Quantity", value: detail.quantity.quantityFormatted)
                if let invested = detail.invested {
                    metricRow(label: "Total invested", value: invested.usdtFormatted)
                }
                metricRow(label: "Proceeds", value: detail.total.usdtFormatted)

                if let pnl = detail.realizedPnL {
                    Divider().opacity(0.2)
                    HStack {
                        Text("Profit / Loss")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        PnLLabel(value: pnl, percentage: pnlPercent, font: .subheadline.bold())
                    }
                }
            }
        }
    }

    private var pnlPercent: Double? {
        guard let invested = detail.invested, invested > 0,
              let pnl = detail.realizedPnL else { return nil }
        return (pnl / invested) * 100
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Previews

#Preview("Day with profit") {
    NavigationStack {
        DayDetailView(
            date: Date(),
            details: [
                DayTradeDetail(
                    id: "BTCUSDT-3", asset: "BTC", symbol: "BTCUSDT",
                    timestamp: Date(), isBuyer: false,
                    price: 67000, quantity: 0.2, total: 13400,
                    costBasisPrice: 48750, invested: 9750, realizedPnL: 3650
                ),
                DayTradeDetail(
                    id: "ETHUSDT-4", asset: "ETH", symbol: "ETHUSDT",
                    timestamp: Date(), isBuyer: true,
                    price: 3200, quantity: 5.0, total: 16000,
                    costBasisPrice: nil, invested: 16000, realizedPnL: nil
                )
            ]
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Day with loss") {
    NavigationStack {
        DayDetailView(
            date: Date(),
            details: [
                DayTradeDetail(
                    id: "SOLUSDT-9", asset: "SOL", symbol: "SOLUSDT",
                    timestamp: Date(), isBuyer: false,
                    price: 95, quantity: 30, total: 2850,
                    costBasisPrice: 120, invested: 3600, realizedPnL: -750
                )
            ]
        )
    }
    .preferredColorScheme(.dark)
}
