//
//  TradingModeBadge.swift
//  EasyCrypto
//
//  Pill-shaped badge indicating the trading mode (Spot, Cross Margin, Isolated Margin).
//  Used in trade history rows, holding rows, and margin overview cards.

import SwiftUI

struct TradingModeBadge: View {
    let mode: TradingMode

    private var color: Color {
        switch mode {
        case .spot: Theme.accent
        case .crossMargin: Theme.marginCross
        case .isolatedMargin: Theme.marginIsolated
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(mode.displayName)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Previews

#Preview("Spot") {
    TradingModeBadge(mode: .spot)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Cross Margin") {
    TradingModeBadge(mode: .crossMargin)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Isolated Margin") {
    TradingModeBadge(mode: .isolatedMargin)
        .padding()
        .preferredColorScheme(.dark)
}
