// ios/PetHomepage/Notifications/NotificationBootstrap.swift
import Foundation

/// Single, testable entry point for asking the user for notification permission
/// and for bulk-cancelling reminders (e.g. during onboarding reset).
enum NotificationBootstrap {
    @discardableResult
    static func requestAuthorizationIfNeeded(using scheduler: NotificationScheduling) async -> Bool {
        await scheduler.requestAuthorization()
    }

    /// Cancels every pending medication reminder (e.g. when all medications are deleted
    /// or the user resets the app). Delegates to the injected scheduler so tests never
    /// touch the real UNUserNotificationCenter.
    static func cancelAllReminders(using scheduler: NotificationScheduling) async {
        await scheduler.cancelAll()
    }
}
