// ios/PetHomepage/Notifications/NotificationBootstrap.swift
import Foundation

/// Single, testable entry point for asking the user for notification permission.
enum NotificationBootstrap {
    @discardableResult
    static func requestAuthorizationIfNeeded(using scheduler: NotificationScheduling) async -> Bool {
        await scheduler.requestAuthorization()
    }
}
