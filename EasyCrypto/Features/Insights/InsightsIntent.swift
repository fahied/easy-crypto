//
//  InsightsIntent.swift
//  EasyCrypto
//

import Foundation

enum InsightsIntent: Intent {
    /// Load persisted insights and current availability (no model call).
    case load
    /// Regenerate insights on-device from the latest trade history.
    case refresh
}
