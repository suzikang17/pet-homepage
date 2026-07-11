// ios/PetHomepageTests/Support/FakeNotificationScheduler.swift
import Foundation
@testable import PetHomepage

/// In-memory fake of NotificationScheduling for unit tests.
/// Replaces (does not duplicate) reminders per (kind, entityID), matching the real adapter.
final class FakeNotificationScheduler: NotificationScheduling {
    private(set) var scheduled: [PendingReminder] = []
    private(set) var authorizationRequestCount = 0
    var authorizationResult = true

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func schedule(_ reminder: PendingReminder) async {
        // Replace key includes the weekly weekday (matches the real adapter's per-request-ID
        // replace). Existing kinds never set a weekday, so their semantics are unchanged.
        scheduled.removeAll {
            $0.kind == reminder.kind && $0.entityID == reminder.entityID
                && $0.dateComponents?.weekday == reminder.dateComponents?.weekday
        }
        scheduled.append(reminder)
    }

    func cancel(kind: ReminderKind, entityID: UUID) async {
        scheduled.removeAll { $0.kind == kind && $0.entityID == entityID }
    }

    func pendingIDs(kind: ReminderKind) async -> [UUID] {
        scheduled.filter { $0.kind == kind }.map(\.entityID)
    }

    func cancelAll(kind: ReminderKind) async {
        scheduled.removeAll { $0.kind == kind }
    }
}

// NOTE: The medication shims the existing tests call —
// `pendingMedicationIDs()`, `cancel(medicationID:)`, and `cancelAll()` (no-arg) —
// are provided as default implementations in the `NotificationScheduling`
// protocol extension in NotificationScheduling.swift, so the fake gets them for
// free and needs NO extra members here. `fake.schedule(PendingMedicationReminder(...))`
// works because `PendingMedicationReminder` is a typealias for `PendingReminder`,
// and `fake.scheduled.first(where: { $0.medicationID == id })` works via the
// `PendingReminder.medicationID` accessor. The three existing medication test files
// (NotificationSchedulerContractTests, NotificationAuthorizationTests,
// MedicationReminderSchedulerTests) therefore compile and pass WITHOUT edits.
