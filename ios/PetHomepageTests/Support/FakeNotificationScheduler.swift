// ios/PetHomepageTests/Support/FakeNotificationScheduler.swift
import Foundation
@testable import PetHomepage

/// In-memory fake of NotificationScheduling for unit tests.
/// Replaces (does not duplicate) reminders per medicationID, matching the real adapter.
final class FakeNotificationScheduler: NotificationScheduling {
    private(set) var scheduled: [PendingMedicationReminder] = []
    private(set) var authorizationRequestCount = 0
    var authorizationResult = true

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func schedule(_ reminder: PendingMedicationReminder) async {
        scheduled.removeAll { $0.medicationID == reminder.medicationID }
        scheduled.append(reminder)
    }

    func cancel(medicationID: UUID) async {
        scheduled.removeAll { $0.medicationID == medicationID }
    }

    func pendingMedicationIDs() async -> [UUID] {
        scheduled.map(\.medicationID)
    }
}
