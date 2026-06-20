// ios/PetHomepageTests/NotificationAuthorizationTests.swift
import XCTest
@testable import PetHomepage

final class NotificationAuthorizationTests: XCTestCase {
    func testBootstrapRequestsAuthorizationAndReturnsGrant() async {
        let fake = FakeNotificationScheduler()
        fake.authorizationResult = true

        let granted = await NotificationBootstrap.requestAuthorizationIfNeeded(using: fake)

        XCTAssertTrue(granted)
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }

    func testBootstrapReturnsFalseWhenDenied() async {
        let fake = FakeNotificationScheduler()
        fake.authorizationResult = false

        let granted = await NotificationBootstrap.requestAuthorizationIfNeeded(using: fake)

        XCTAssertFalse(granted)
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }

    func testCancelAllRemindersRemovesAllPendingReminders() async {
        let fake = FakeNotificationScheduler()
        // Pre-populate two scheduled reminders via the fake scheduler directly.
        let id1 = UUID()
        let id2 = UUID()
        await fake.schedule(PendingMedicationReminder(medicationID: id1,
                                                      title: "T", body: "B", hour: 8, minute: 0))
        await fake.schedule(PendingMedicationReminder(medicationID: id2,
                                                      title: "T", body: "B", hour: 20, minute: 0))

        await NotificationBootstrap.cancelAllReminders(using: fake)

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty, "cancelAllReminders should clear every pending reminder")
    }
}
