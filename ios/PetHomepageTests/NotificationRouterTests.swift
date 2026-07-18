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

    func testUnknownIdentifierDoesNotNavigate() {
        let router = NotificationRouter()
        router.route(requestID: "medication-reminder-\(UUID().uuidString)")
        XCTAssertNil(router.pendingTab)
    }
}
