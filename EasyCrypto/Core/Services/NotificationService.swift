//
//  NotificationService.swift
//  EasyCrypto
//

import Foundation
import UserNotifications

// MARK: - Types

/// A local notification to deliver to the user.
nonisolated struct LocalAlert: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
}

// MARK: - Service (struct-with-closures pattern)

nonisolated struct NotificationService: Sendable {
    /// Requests notification authorization; returns whether it was granted.
    var requestAuthorization: @Sendable () async -> Bool
    /// Whether notifications are currently authorized (or provisionally authorized).
    var isAuthorized: @Sendable () async -> Bool
    /// Delivers a local notification immediately. Silently dropped by the system
    /// when authorization has not been granted.
    var scheduleAlert: @Sendable (_ alert: LocalAlert) async -> Void
}

// MARK: - Live Implementation

extension NotificationService {
    static let live = NotificationService(
        requestAuthorization: {
            (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
        },
        isAuthorized: {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        },
        scheduleAlert: { alert in
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: alert.id,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    )
}

// MARK: - Preview & Noop

extension NotificationService {
    static let preview = NotificationService(
        requestAuthorization: { true },
        isAuthorized: { true },
        scheduleAlert: { _ in }
    )

    static let noop = NotificationService(
        requestAuthorization: { false },
        isAuthorized: { false },
        scheduleAlert: { _ in }
    )
}
