// ios/PetHomepage/Notifications/NotificationScheduling.swift
import Foundation

/// A single daily medication reminder, expressed independently of UserNotifications
/// so scheduling logic is pure and testable.
struct PendingMedicationReminder: Equatable {
    let medicationID: UUID
    let title: String
    let body: String
    let hour: Int
    let minute: Int
}

/// Abstraction over the system notification center so scheduling logic can be
/// unit-tested with a fake (no real UNUserNotificationCenter, no permission prompt).
protocol NotificationScheduling {
    /// Requests notification authorization; returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Schedules (or replaces) the daily reminder for a medication.
    func schedule(_ reminder: PendingMedicationReminder) async
    /// Cancels any pending reminder for the given medication.
    func cancel(medicationID: UUID) async
    /// The medication IDs that currently have a pending reminder.
    func pendingMedicationIDs() async -> [UUID]
}

/// Deterministic request identifier shared by the real and fake schedulers,
/// so schedule/cancel/replace are idempotent per medication.
enum MedicationReminderIdentifier {
    static let prefix = "med-reminder-"

    static func requestID(for medicationID: UUID) -> String {
        prefix + medicationID.uuidString
    }

    static func medicationID(from requestID: String) -> UUID? {
        guard requestID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(requestID.dropFirst(prefix.count)))
    }
}
