// ios/PetHomepageTests/NotificationRouterTests.swift
import XCTest

@testable import PetHomepage

@MainActor
final class NotificationRouterTests: XCTestCase {
    func testRoutineReminderRoutesToSchedule() {
        let router = NotificationRouter()
        router.route(requestID: "routine-reminder-\(UUID().uuidString)-d20260718")
        XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.schedule.rawValue)
    }

    func testWalkNotificationsRouteToSchedule() {
        for id in ["walk-ended-\(UUID().uuidString)-1700000000",
                   "walk-detected-r-\(UUID().uuidString)-1700000000",
                   "walk-autostarted-\(UUID().uuidString)"] {
            let router = NotificationRouter()
            router.route(requestID: id)
            XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.schedule.rawValue, id)
        }
    }

    /// Medication reminders land on Timeline, which owns the medication rows and the Log dose
    /// flow. Previously they routed nowhere, so tapping a dose reminder dumped you on whatever
    /// tab you happened to leave the app on.
    func testMedicationReminderRoutesToTimeline() {
        for id in ["medication-reminder-\(UUID().uuidString)",
                   "medicationSnooze-reminder-\(UUID().uuidString)"] {
            let router = NotificationRouter()
            router.route(requestID: id)
            XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.timeline.rawValue, id)
        }
    }

    /// Vaccination / vet-cadence / activity due reminders are still unrouted — a known gap.
    func testUnknownIdentifierDoesNotNavigate() {
        let router = NotificationRouter()
        router.route(requestID: "vaccination-reminder-\(UUID().uuidString)")
        XCTAssertNil(router.pendingTab)
    }
}
