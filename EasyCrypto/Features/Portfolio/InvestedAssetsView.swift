//
//  InvestedAssetsView.swift
//  EasyCrypto
//
//  Detail view shown when the user taps "Total Invested" on the Portfolio tab.
//  Lists every asset with invested amount and current value across all trading modes.

import SwiftUI

struct InvestedAssetsView: View {
    let destination: InvestedAssetsDestination

    var body: some View {
        List {
            Section {
                totalSummaryRow
            }

            Section {
                ForEach(destination.assets) { row in
                    InvestedAssetRowView(row: row)
                }
            }
        }
        .navigationTitle("Invested Assets")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Total Summary

    private var totalSummaryRow: some View {
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

            // Amount invested → current value
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.amountInvestedUSDT.usdtFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(row.currentValueUSDT.usdtFormatted)
                    .font(.subheadline.bold())
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Previews

#Preview("Multiple Assets") {
    let destination = InvestedAssetsDestination(
        assets: [
            InvestedAssetRow(asset: "BTC", tradingMode: .spot, amountInvestedUSDT: 25000, currentValueUSDT: 32500),
            InvestedAssetRow(asset: "ETH", tradingMode: .spot, amountInvestedUSDT: 15000, currentValueUSDT: 17500),
            InvestedAssetRow(asset: "BTC", tradingMode: .crossMargin, amountInvestedUSDT: 10000, currentValueUSDT: 13000),
            InvestedAssetRow(asset: "BNB", tradingMode: .isolatedMargin, amountInvestedUSDT: 5000, currentValueUSDT: 6200),
        ],
        totalInvested: 55000,
        totalCurrentValue: 69200
    )
    NavigationStack {
        InvestedAssetsView(destination: destination)
            .preferredColorScheme(.dark)
    }
}

#Preview("Single Asset") {
    let destination = InvestedAssetsDestination(
        assets: [
            InvestedAssetRow(asset: "BTC", tradingMode: .spot, amountInvestedUSDT: 25000, currentValueUSDT: 32500),
        ],
        totalInvested: 25000,
        totalCurrentValue: 32500
    )
    NavigationStack {
        InvestedAssetsView(destination: destination)
            .preferredColorScheme(.dark)
    }
}
