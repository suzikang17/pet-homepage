// ios/PetHomepageTests/ReminderIdentifierWeekdayTests.swift
import XCTest
@testable import PetHomepage

final class ReminderIdentifierWeekdayTests: XCTestCase {
    private let id = UUID()

    private func weekly(_ weekday: Int) -> PendingReminder {
        PendingReminder(kind: .routine, entityID: id, title: "Walk", body: "Time for a walk",
                        hour: 8, minute: 0, dateComponents: DateComponents(weekday: weekday),
                        repeats: true)
    }

    func testWeeklyRequestIDsCarryWeekdaySuffix() {
        XCTAssertEqual(ReminderIdentifier.requestID(for: weekly(3)),
                       "routine-reminder-\(id.uuidString)-w3")
        // Non-weekly reminders keep the bare ID (back-compat with everything shipped).
        let daily = PendingReminder(kind: .medication, entityID: id, title: "t", body: "b",
                                    hour: 9, minute: 0)
        XCTAssertEqual(ReminderIdentifier.requestID(for: daily),
                       "medication-reminder-\(id.uuidString)")
    }

    func testParseHandlesWeekdaySuffix() throws {
        let (kind, parsed) = try XCTUnwrap(
            ReminderIdentifier.parse("routine-reminder-\(id.uuidString)-w5"))
        XCTAssertEqual(kind, .routine)
        XCTAssertEqual(parsed, id)
        // Bare IDs still parse.
        XCTAssertNotNil(ReminderIdentifier.parse("routine-reminder-\(id.uuidString)"))
        XCTAssertNil(ReminderIdentifier.parse("routine-reminder-not-a-uuid-w5"))
    }

    func testRequestIDsForCancelCoverBaseAndAllWeekdays() {
        let ids = ReminderIdentifier.requestIDs(kind: .routine, entityID: id)
        XCTAssertEqual(ids.count, 8)
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)"))
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)-w1"))
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)-w7"))
    }

    func testFakeSchedulerKeepsPerWeekdayReminders() async {
        let fake = FakeNotificationScheduler()
        await fake.schedule(weekly(2))
        await fake.schedule(weekly(4))
        XCTAssertEqual(fake.scheduled.count, 2) // distinct weekdays coexist
        await fake.schedule(weekly(2))
        XCTAssertEqual(fake.scheduled.count, 2) // same weekday replaces
        await fake.cancel(kind: .routine, entityID: id)
        XCTAssertEqual(fake.scheduled.count, 0) // cancel clears every weekday
    }

    func testPendingReminderDefaultsPreserveBackCompat() {
        let medication = PendingMedicationReminder(medicationID: id, title: "t", body: "b",
                                                   hour: 9, minute: 0)
        XCTAssertFalse(medication.repeats)
        XCTAssertNil(medication.dateComponents)
    }
}
