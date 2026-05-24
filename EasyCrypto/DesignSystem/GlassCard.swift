//
//  GlassCard.swift
//  EasyCrypto
//

import SwiftUI

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(Theme.cardSpacing + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Previews

#Preview("Default content") {
    Text("Hello, Glass!")
        .font(.headline)
        .glassCard()
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Long text") {
    VStack(alignment: .leading, spacing: 8) {
        Text("Portfolio Summary")
            .font(.headline)
        Text("This is a longer description that demonstrates how the glass card handles multiline text content gracefully across multiple lines.")
            .font(.body)
            .foregroundStyle(.secondary)
    }
    .glassCard()
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Nested content") {
    VStack {
        HStack {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.title)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading) {
                Text("Bitcoin")
                    .font(.headline)
                Text("BTC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("$65,000.00")
                .font(.title3.bold())
        }
    }
    .glassCard()
    .padding()
    .preferredColorScheme(.dark)
}
