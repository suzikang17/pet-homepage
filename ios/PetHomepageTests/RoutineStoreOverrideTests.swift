// ios/PetHomepageTests/RoutineStoreOverrideTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreOverrideTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
    }

    private func makeTask(_ name: String = "Walk", hour: Int = 8) throws -> RoutineTask {
        try store.createTask(name: name, category: .play, iconName: "figure.walk",
                             hour: hour, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testOverrideMovesSlotTimeForThatDayOnly() throws {
        let task = try makeTask()
        try store.overrideTime(task, on: today, hour: 15, minute: 30)

        let slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertEqual(slot.hour, 15)
        XCTAssertEqual(slot.minute, 30)
        XCTAssertNotNil(slot.timeOverride)
        // Other days keep the template time.
        let tomorrow = try XCTUnwrap(try store.slots(for: day(1)).first)
        XCTAssertEqual(tomorrow.hour, 8)
        XCTAssertNil(tomorrow.timeOverride)
        // Template row itself untouched.
        XCTAssertEqual(task.hour, 8)
    }

    func testOverrideUpsertsAndClears() throws {
        let task = try makeTask()
        try store.overrideTime(task, on: today, hour: 15, minute: 0)
        try store.overrideTime(task, on: today, hour: 16, minute: 45)
        XCTAssertEqual(try context.fetch(RoutineOverride.fetchRequest()).count, 1) // upsert
        XCTAssertEqual(try XCTUnwrap(try store.slots(for: today).first).hour, 16)

        try store.clearOverrideTime(task, on: today)
        XCTAssertEqual(try context.fetch(RoutineOverride.fetchRequest()).count, 0)
        XCTAssertEqual(try XCTUnwrap(try store.slots(for: today).first).hour, 8)
    }

    func testOverrideResortsTheDay() throws {
        try makeTask("Breakfast", hour: 7)
        let walk = try makeTask("Walk", hour: 8)
        // Move the walk to the evening, today only: it should sort after Breakfast... and
        // after a 9:00 task too.
        try makeTask("Playtime", hour: 9)
        try store.overrideTime(walk, on: today, hour: 19, minute: 0)
        XCTAssertEqual(try store.slots(for: today).map(\.task.name),
                       ["Breakfast", "Playtime", "Walk"])
        XCTAssertEqual(try store.slots(for: day(1)).map(\.task.name),
                       ["Breakfast", "Walk", "Playtime"])
    }

    func testPastDayCheckOffUsesOverrideTime() throws {
        let task = try makeTask()
        try store.overrideTime(task, on: day(-2), hour: 15, minute: 30)
        let entry = try store.checkOff(task, on: day(-2))
        let comps = calendar.dateComponents([.hour, .minute], from: entry.performedAt)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 30)
    }

    func testUpdateCompletionTimeStaysOnItsDay() throws {
        let task = try makeTask()
        let entry = try store.checkOff(task, on: day(-1))
        try store.updateCompletionTime(entry, hour: 21, minute: 15)
        let comps = calendar.dateComponents([.hour, .minute], from: entry.performedAt)
        XCTAssertEqual(comps.hour, 21)
        XCTAssertEqual(comps.minute, 15)
        XCTAssertTrue(calendar.isDate(entry.performedAt, inSameDayAs: day(-1)))
        // Still overlays the same slot.
        XCTAssertTrue(try XCTUnwrap(try store.slots(for: day(-1)).first).isCompleted)
    }

    func testCheckOffAttachesTasksOwnPetNotActivePet() throws {
        let task = try makeTask() // belongs to Sandy
        let second = try petStore.createPet(name: "Milo", species: "cat")
        petStore.setActivePet(second)
        let entry = try store.checkOff(task, on: today)
        XCTAssertEqual(entry.pet?.name, "Sandy") // the task's pet, not the active pet
    }

    func testCompletionLookupIsPetIndependent() throws {
        let task = try makeTask()
        XCTAssertNil(try store.completion(of: task, on: today))
        let entry = try store.checkOff(task, on: today)
        let second = try petStore.createPet(name: "Milo", species: "cat")
        petStore.setActivePet(second)
        XCTAssertEqual(try store.completion(of: task, on: today)?.id, entry.id)
    }
}
