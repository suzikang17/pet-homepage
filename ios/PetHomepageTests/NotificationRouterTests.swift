// ios/PetHomepageTests/NotificationRouterTests.swift
import XCTest

@testable import PetHomepage

@MainActor
final class NotificationRouterTests: XCTestCase {
    func testRoutineReminderRoutesToScheduleOnToday() {
        let router = NotificationRouter()
        router.route(requestID: "routine-reminder-\(UUID().uuidString)-d20260718")
        XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.schedule.rawValue)
        // Routine reminders act on the day's checklist, so they must NOT be dragged onto Log
        // along with the medication re-route.
        XCTAssertEqual(router.pendingScheduleTab, .today)
    }

    func testWalkNotificationsRouteToScheduleOnToday() {
        for id in ["walk-ended-\(UUID().uuidString)-1700000000",
                   "walk-detected-r-\(UUID().uuidString)-1700000000",
                   "walk-autostarted-\(UUID().uuidString)"] {
            let router = NotificationRouter()
            router.route(requestID: id)
            XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.schedule.rawValue, id)
            XCTAssertEqual(router.pendingScheduleTab, .today, id)
        }
    }

    /// Medication reminders act on the medication rows and the dose history. Those used to live
    /// on tab 1, so that is where these routed — but tab 1 is now the photo Gallery, and a
    /// tapped dose reminder landing on pictures is the regression this guards.
    func testMedicationReminderRoutesToScheduleOnLog() {
        for id in ["medication-reminder-\(UUID().uuidString)",
                   "medicationSnooze-reminder-\(UUID().uuidString)"] {
            let router = NotificationRouter()
            router.route(requestID: id)
            XCTAssertEqual(router.pendingTab, NotificationRouter.Tab.schedule.rawValue, id)
            XCTAssertNotEqual(router.pendingTab, NotificationRouter.Tab.gallery.rawValue, id)
            XCTAssertEqual(router.pendingScheduleTab, .log, id)
        }
    }

    /// The tab tags are mapped by raw value from `ContentView`'s `.tag`, so renaming or
    /// reordering a tab must never renumber them.
    func testTabTagsAreStable() {
        XCTAssertEqual(NotificationRouter.Tab.home.rawValue, 0)
        XCTAssertEqual(NotificationRouter.Tab.gallery.rawValue, 1)
        XCTAssertEqual(NotificationRouter.Tab.schedule.rawValue, 3)
        XCTAssertEqual(NotificationRouter.Tab.careTeam.rawValue, 4)
    }

    /// Vaccination / vet-cadence / activity due reminders are still unrouted — a known gap.
    func testUnknownIdentifierDoesNotNavigate() {
        let router = NotificationRouter()
        router.route(requestID: "vaccination-reminder-\(UUID().uuidString)")
        XCTAssertNil(router.pendingTab)
        XCTAssertNil(router.pendingScheduleTab)
    }
}
