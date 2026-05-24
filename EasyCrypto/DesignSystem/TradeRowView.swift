//
//  TradeRowView.swift
//  EasyCrypto
//

import SwiftUI

struct TradeRowView: View {
    let date: Date
    let isBuyer: Bool
    let price: Double
    let quantity: Double
    let total: Double

    private var sideColor: Color {
        isBuyer ? Theme.profit : Theme.loss
    }

    private var sideLabel: String {
        isBuyer ? "BUY" : "SELL"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Side indicator
            Text(sideLabel)
                .font(.caption.bold())
                .foregroundStyle(sideColor)
                .frame(width: 36)

            // Date & price
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("@ \(price.usdtFormatted)")
                    .font(.subheadline)
            }

            Spacer()

            // Quantity & total
            VStack(alignment: .trailing, spacing: 2) {
                Text(quantity.quantityFormatted)
                    .font(.subheadline)
                Text(total.usdtFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Buy trade") {
    TradeRowView(
        date: Date(),
        isBuyer: true,
        price: 65000.50,
        quantity: 0.5,
        total: 32500.25
    )
    .glassCard()
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Sell trade") {
    TradeRowView(
        date: Date(),
        isBuyer: false,
        price: 67500.00,
        quantity: 0.2,
        total: 13500.00
    )
    .glassCard()
    .padding()
    .preferredColorScheme(.dark)
}
