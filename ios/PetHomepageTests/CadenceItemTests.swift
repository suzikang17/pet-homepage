// ios/PetHomepageTests/CadenceItemTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class CadenceItemTests: XCTestCase {
    private var calendar: Calendar!
    private var objectID: NSManagedObjectID!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        let context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        objectID = try XCTUnwrap(petStore.currentPet()).objectID
    }

    private func item(nextDue: Date?) -> CadenceItem {
        CadenceItem(id: UUID(), source: .activityType(objectID), name: "Bath",
                    iconName: "shower", subtitle: nil, lastDone: nil, nextDue: nextDue)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testNilNextDueIsNoCadence() {
        let now = date(2026, 8, 16)
        XCTAssertEqual(item(nextDue: nil).dueState(now: now, calendar: calendar), .noCadence)
    }

    func testDueLaterTodayIsDueToday() {
        let now = date(2026, 8, 16, 9)
        // Due at 17:00 today: still "due today", never "overdue".
        let state = item(nextDue: date(2026, 8, 16, 17)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueToday)
    }

    func testDueEarlierTodayIsStillDueToday() {
        let now = date(2026, 8, 16, 23)
        // Due at 09:00, it is now 23:00 the same day — day granularity means NOT overdue.
        let state = item(nextDue: date(2026, 8, 16, 9)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueToday)
    }

    func testDueYesterdayIsOverdueByOneDay() {
        let now = date(2026, 8, 16, 9)
        let state = item(nextDue: date(2026, 8, 15, 9)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .overdue(days: 1))
    }

    func testDueTomorrowIsDueInOneDay() {
        let now = date(2026, 8, 16, 23)
        let state = item(nextDue: date(2026, 8, 17, 1)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueIn(days: 1))
    }
}
