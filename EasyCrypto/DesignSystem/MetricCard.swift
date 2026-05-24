//
//  MetricCard.swift
//  EasyCrypto
//

import SwiftUI

struct MetricCard: View {
    let label: String
    let value: String
    var subtitle: String?
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .glassCard()
    }
}

// MARK: - Previews

#Preview("With subtitle") {
    MetricCard(
        label: "Total Invested",
        value: "$25,000.00",
        subtitle: "Across 5 assets"
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Without subtitle") {
    MetricCard(
        label: "Current Value",
        value: "$32,500.00",
        valueColor: Theme.profit
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Large value") {
    MetricCard(
        label: "Unrealized P&L",
        value: "+$1,250,000.00",
        subtitle: "+450.25%",
        valueColor: Theme.profit
    )
    .padding()
    .preferredColorScheme(.dark)
}
