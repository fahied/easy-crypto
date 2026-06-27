//
//  CandleAlertState.swift
//  EasyCrypto
//

import Foundation
import SwiftData

/// Single-row persistence for the hourly candle-drop check throttle.
///
/// `lastCheckedAt` records when the candle-drop evaluation last ran so the check
/// runs at most once per hour. iOS background wakes are best-effort, so this
/// approximates an hourly cadence rather than guaranteeing a wall-clock hour.
@Model
final class CandleAlertState {
    var lastCheckedAt: Date

    init(lastCheckedAt: Date = .distantPast) {
        self.lastCheckedAt = lastCheckedAt
    }
}
