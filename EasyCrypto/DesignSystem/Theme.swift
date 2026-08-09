//
//  Theme.swift
//  EasyCrypto
//

import SwiftUI

enum Theme {
    // Binance-inspired palette
    static let accent = Color(red: 0.94, green: 0.73, blue: 0.04) // #F0B90B
    static let profit = Color(red: 0.13, green: 0.82, blue: 0.44)
    static let loss = Color(red: 1.0, green: 0.27, blue: 0.33)
    static let neutral = Color.secondary

    // Margin-specific colors
    static let marginCross = Color(red: 0.98, green: 0.50, blue: 0.13)      // orange tint
    static let marginIsolated = Color(red: 0.60, green: 0.40, blue: 0.95)     // purple tint

    // Corner radii
    static let cardRadius: CGFloat = 20
    static let smallRadius: CGFloat = 12

    // Spacing
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
}

// MARK: - Formatting Helpers

extension Double {
    var usdtFormatted: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    var signedUsdtFormatted: String {
        let prefix = self >= 0 ? "+" : ""
        return "\(prefix)\(usdtFormatted)"
    }

    var percentFormatted: String {
        let prefix = self >= 0 ? "+" : ""
        return "\(prefix)\(formatted(.number.precision(.fractionLength(2))))%"
    }

    var quantityFormatted: String {
        if self >= 1 {
            return formatted(.number.precision(.fractionLength(4)))
        } else {
            return formatted(.number.precision(.fractionLength(8)))
        }
    }
}
