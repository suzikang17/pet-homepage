// ios/PetHomepage/Notifications/NotificationBootstrap.swift
import Foundation
import UserNotifications

/// Single, testable entry point for asking the user for notification permission
/// and for bulk-cancelling reminders (e.g. during onboarding reset).
enum NotificationBootstrap {
    /// Registers every actionable category (routine + walk + medication) in one call —
    /// setNotificationCategories replaces the set, so composition must happen here.
    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(
            RoutineNotificationAction.categories()
                .union(WalkNotificationAction.categories())
                .union(MedicationNotificationAction.categories())
        )
    }

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
