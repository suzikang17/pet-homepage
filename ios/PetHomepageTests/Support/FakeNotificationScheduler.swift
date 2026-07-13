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
        // Replace key mirrors the real adapter exactly: the full request identifier, which
        // carries the weekly-weekday or routine per-day suffix when present.
        let id = ReminderIdentifier.requestID(for: reminder)
        scheduled.removeAll { ReminderIdentifier.requestID(for: $0) == id }
        scheduled.append(reminder)
    }

    func cancel(kind: ReminderKind, entityID: UUID) async {
        scheduled.removeAll { $0.kind == kind && $0.entityID == entityID }
    }

    func pendingIDs(kind: ReminderKind) async -> [UUID] {
        // Dedupe like the real adapter: a routine task's per-weekday reminders share one entityID.
        var seen = Set<UUID>()
        return scheduled.filter { $0.kind == kind && seen.insert($0.entityID).inserted }.map(\.entityID)
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
