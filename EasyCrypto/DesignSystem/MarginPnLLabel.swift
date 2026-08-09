//
//  MarginPnLLabel.swift
//  EasyCrypto
//
//  Extends PnLLabel with an optional borrowing fee subtitle.
//  Shows "−$123.45 P&L (fee: $12.34)" when fee > 0,
//  falls back to standard PnLLabel when fee is nil or zero.

import SwiftUI

struct MarginPnLLabel: View {
    let value: Double
    var percentage: Double?
    var borrowingFee: Double?
    var showArrow: Bool = true
    var font: Font = .subheadline.bold()

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            PnLLabel(
                value: value,
                percentage: percentage,
                showArrow: showArrow,
                font: font
            )

            if let fee = borrowingFee, fee > 1e-12 {
                Text("fee: \(fee.usdtFormatted)")
                    .font(.caption2)
                    .foregroundStyle(Theme.loss.opacity(0.7))
            }
        }
    }
}

// MARK: - Previews

#Preview("With fee") {
    MarginPnLLabel(value: 2500, percentage: 5.2, borrowingFee: 12.34)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("No fee") {
    MarginPnLLabel(value: 2500, percentage: 5.2)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Negative P&L with fee") {
    MarginPnLLabel(value: -800, percentage: -3.1, borrowingFee: 45.67)
        .padding()
        .preferredColorScheme(.dark)
}
