//
//  PnLLabel.swift
//  EasyCrypto
//

import SwiftUI

struct PnLLabel: View {
    let value: Double
    var percentage: Double?
    var showArrow: Bool = true
    var font: Font = .subheadline.bold()

    private var color: Color {
        if value > 0 { return Theme.profit }
        if value < 0 { return Theme.loss }
        return Theme.neutral
    }

    var body: some View {
        HStack(spacing: 4) {
            if showArrow {
                Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .imageScale(.small)
            }
            Text(value.signedUsdtFormatted)
            if let percentage {
                Text("(\(percentage.percentFormatted))")
            }
        }
        .font(font)
        .foregroundStyle(color)
    }
}

// MARK: - Previews

#Preview("Positive P&L") {
    PnLLabel(value: 10_250.75, percentage: 23.45)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Negative P&L") {
    PnLLabel(value: -3_420.50, percentage: -12.30)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Zero / Neutral") {
    PnLLabel(value: 0, percentage: 0)
        .padding()
        .preferredColorScheme(.dark)
}
