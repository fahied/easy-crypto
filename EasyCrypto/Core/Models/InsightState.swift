//
//  InsightState.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Single-row persistence for the AI-insight regeneration throttle.
///
/// `lastGeneratedAt` records when insights were last generated so regeneration runs
/// at most once every 4 hours. iOS background wakes are best-effort, so this
/// approximates a 4-hour cadence rather than guaranteeing a wall-clock interval.
/// Mirrors `CandleAlertState`.
@Model
final class InsightState {
    var lastGeneratedAt: Date

    init(lastGeneratedAt: Date = .distantPast) {
        self.lastGeneratedAt = lastGeneratedAt
    }
}
