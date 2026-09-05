//
//  InvestedAssetsView.swift
//  EasyCrypto
//
//  Detail view shown when the user taps "Total Invested" on the Portfolio tab.
//  Lists every asset with invested amount and current value across all trading modes.

import SwiftUI

struct InvestedAssetsView: View {
    let destination: InvestedAssetsDestination
    let onSelectAsset: (String, TradingMode) -> Void

    var body: some View {
        List {
            Section {
                totalSummaryRow
            }

            Section {
                ForEach(destination.assets) { row in
                    InvestedAssetRowView(row: row)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectAsset(row.asset, row.tradingMode)
                        }
                }
            }
        }
        .navigationTitle("Invested Assets")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Total Summary

    private var totalSummaryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Invested")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(destination.totalInvested.usdtFormatted)
                        .font(.title3.bold())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(destination.totalCurrentValue.usdtFormatted)
                        .font(.title3.bold())
                }
            }

            if destination.totalInvested > 0 {
                HStack {
                    Spacer()
                    PnLLabel(
                        value: destination.totalPnL,
                        percentage: destination.totalPnLPercent,
                        font: .subheadline
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invested Asset Row

struct InvestedAssetRowView: View {
    let row: InvestedAssetRow

    var body: some View {
        HStack(spacing: 12) {
            // Asset name + trading mode badge
            VStack(alignment: .leading, spacing: 4) {
                Text(row.asset)
                    .font(.body.bold())

                TradingModeBadge(mode: row.tradingMode)
            }

            Spacer()

            // Amount invested → current value → P&L
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.amountInvestedUSDT.usdtFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(row.currentValueUSDT.usdtFormatted)
                    .font(.subheadline.bold())

                if row.amountInvestedUSDT > 0 {
                    PnLLabel(
                        value: row.unrealizedPnL,
                        percentage: row.unrealizedPnLPercent,
                        font: .caption
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Previews

#Preview("Multiple Assets") {
    let destination = InvestedAssetsDestination(
        assets: [
            InvestedAssetRow(asset: "BTC", tradingMode: .spot, amountInvestedUSDT: 25000, currentValueUSDT: 32500,
                             unrealizedPnL: 7500, unrealizedPnLPercent: 30),
            InvestedAssetRow(asset: "ETH", tradingMode: .spot, amountInvestedUSDT: 15000, currentValueUSDT: 17500,
                             unrealizedPnL: 2500, unrealizedPnLPercent: 16.67),
            InvestedAssetRow(asset: "BTC", tradingMode: .crossMargin, amountInvestedUSDT: 10000, currentValueUSDT: 13000,
                             unrealizedPnL: 3000, unrealizedPnLPercent: 30),
            InvestedAssetRow(asset: "BNB", tradingMode: .isolatedMargin, amountInvestedUSDT: 5000, currentValueUSDT: 6200,
                             unrealizedPnL: 1200, unrealizedPnLPercent: 24),
        ],
        totalInvested: 55000,
        totalCurrentValue: 69200,
        totalPnL: 14200,
        totalPnLPercent: 25.82
    )
    NavigationStack {
        InvestedAssetsView(destination: destination) { _, _ in }
            .preferredColorScheme(.dark)
    }
}

#Preview("Single Asset") {
    let destination = InvestedAssetsDestination(
        assets: [
            InvestedAssetRow(asset: "BTC", tradingMode: .spot, amountInvestedUSDT: 25000, currentValueUSDT: 32500,
                             unrealizedPnL: 7500, unrealizedPnLPercent: 30),
        ],
        totalInvested: 25000,
        totalCurrentValue: 32500,
        totalPnL: 7500,
        totalPnLPercent: 30
    )
    NavigationStack {
        InvestedAssetsView(destination: destination) { _, _ in }
            .preferredColorScheme(.dark)
    }
}
