// ios/PetHomepageTests/RoutineTaskModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineTaskModelTests: XCTestCase {
    func testWeekdayMaskHelpers() {
        // Calendar weekdays: 1 = Sunday … 7 = Saturday; bit = weekday - 1.
        XCTAssertEqual(Weekdays.all, 0b111_1111)
        XCTAssertEqual(Weekdays.bit(for: 1), 0b000_0001) // Sunday
        XCTAssertEqual(Weekdays.bit(for: 7), 0b100_0000) // Saturday
        XCTAssertEqual(Weekdays.mask(of: [3, 5]), 0b001_0100) // Tue + Thu
        XCTAssertTrue(Weekdays.contains(0b001_0100, weekday: 3))
        XCTAssertFalse(Weekdays.contains(0b001_0100, weekday: 2))
        XCTAssertEqual(Weekdays.weekdays(in: 0b001_0100), [3, 5])
        XCTAssertEqual(Weekdays.weekdays(in: Weekdays.all), [1, 2, 3, 4, 5, 6, 7])
    }

    func testRoutineEntitiesInsertAndFetch() throws {
        let context = PersistenceController(inMemory: true).container.viewContext

        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Morning walk"
        task.category = .play
        task.iconName = "figure.walk"
        task.hour = 8
        task.minute = 0
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date()

        let skip = RoutineSkip(context: context)
        skip.id = UUID()
        skip.date = Date()
        skip.taskLineageID = task.lineageID

        try context.save()

        XCTAssertEqual(try context.fetch(RoutineTask.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(RoutineTask.fetchRequest()).first?.category, .play)
        XCTAssertNil(task.effectiveUntil)
        XCTAssertFalse(task.isOneOff)
    }

    func testLogEntryRoutineKindAndLineage() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = Date()
        entry.kind = .routine
        entry.routineLineageID = UUID()
        try context.save()
        XCTAssertEqual(entry.kindRaw, "routine")
        XCTAssertNotNil(entry.routineLineageID)
    }
}
