// ios/PetHomepageTests/RoutineStoreDurationTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class RoutineStoreDurationTests: XCTestCase {
    func testCheckOffWithSessionTimesStoresSpan() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "routine-duration-\(UUID().uuidString)")!)
        let store = RoutineStore(context: context, petStore: petStore, calendar: .current)

        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Evening walk"
        task.categoryRaw = ActivityCategory.training.rawValue
        task.iconName = "figure.walk"
        task.hour = 17
        task.minute = 30
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date(timeIntervalSince1970: 0)
        task.isOneOff = false
        try context.save()

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(45 * 60)
        let entry = try store.checkOff(task, on: end, now: end, startedAt: start, endedAt: end)
        XCTAssertEqual(entry.performedAt, start)
        XCTAssertEqual(entry.endedAt, end)
        XCTAssertEqual(entry.durationMinutes, 45)
    }

    func testCheckOffWithoutSessionKeepsSingleTimestamp() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "routine-duration-\(UUID().uuidString)")!)
        let store = RoutineStore(context: context, petStore: petStore, calendar: .current)

        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Breakfast"
        task.categoryRaw = ActivityCategory.feeding.rawValue
        task.iconName = "fork.knife"
        task.hour = 8
        task.minute = 0
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date(timeIntervalSince1970: 0)
        task.isOneOff = false
        try context.save()

        let now = Date()
        let entry = try store.checkOff(task, on: now, now: now)
        XCTAssertNil(entry.endedAt)
        XCTAssertNil(entry.durationMinutes)
    }
}
