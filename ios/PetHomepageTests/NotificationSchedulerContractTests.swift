// ios/PetHomepageTests/NotificationSchedulerContractTests.swift
import XCTest
@testable import PetHomepage

final class NotificationSchedulerContractTests: XCTestCase {
    private func reminder(_ id: UUID, hour: Int = 18, minute: Int = 0) -> PendingMedicationReminder {
        PendingMedicationReminder(medicationID: id,
                                  title: "Time for meds",
                                  body: "Give Apoquel",
                                  hour: hour,
                                  minute: minute)
    }

    func testFakeRecordsScheduledReminders() async {
        let fake = FakeNotificationScheduler()
        let id = UUID()
        await fake.schedule(reminder(id))

        let pending = await fake.pendingMedicationIDs()
        XCTAssertEqual(pending, [id])
        XCTAssertEqual(fake.scheduled.last?.hour, 18)
    }

    func testSchedulingSameMedicationIDReplacesNotDuplicates() async {
        let fake = FakeNotificationScheduler()
        let id = UUID()
        await fake.schedule(reminder(id, hour: 8))
        await fake.schedule(reminder(id, hour: 20))

        let pending = await fake.pendingMedicationIDs()
        XCTAssertEqual(pending, [id])
        XCTAssertEqual(fake.scheduled.first(where: { $0.medicationID == id })?.hour, 20)
    }

    func testCancelRemovesReminder() async {
        let fake = FakeNotificationScheduler()
        let id = UUID()
        await fake.schedule(reminder(id))
        await fake.cancel(medicationID: id)

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testRequestAuthorizationReturnsConfiguredResult() async {
        let fake = FakeNotificationScheduler()
        fake.authorizationResult = false
        let granted = await fake.requestAuthorization()
        XCTAssertFalse(granted)
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }

    // TDD red commit: cancelAll() does not yet exist on the protocol or fake.
    // This test must fail (compile error) before the implementation is added.
    func testCancelAllRemovesAllPendingReminders() async {
        let fake = FakeNotificationScheduler()
        let idA = UUID()
        let idB = UUID()
        await fake.schedule(reminder(idA, hour: 8))
        await fake.schedule(reminder(idB, hour: 20))

        await fake.cancelAll()

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty, "cancelAll() should clear every pending reminder")
    }
}
