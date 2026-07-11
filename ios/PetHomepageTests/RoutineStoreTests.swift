// ios/PetHomepageTests/RoutineStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private let calendar = Calendar.current

    /// A fixed "today" so tests are deterministic regardless of wall clock.
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

    func testCreateTaskIsListedAndScopedToPet() throws {
        let task = try store.createTask(name: "Morning walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertNotNil(task.lineageID)
        let tasks = try store.currentTasks()
        XCTAssertEqual(tasks.map(\.name), ["Morning walk"])
        XCTAssertEqual(tasks.first?.pet?.name, "Sandy")
        XCTAssertNil(tasks.first?.effectiveUntil)
    }

    func testCurrentTasksSortByTime() throws {
        try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                             hour: 18, minute: 0, weekdayMask: Weekdays.all)
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Breakfast", "Dinner"])
    }

    func testEditOfHistoricalTaskClosesRowAndSpawnsSuccessor() throws {
        let original = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                            hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                            from: day(-10))
        let successor = try store.editTask(original, name: "Long walk", category: .play,
                                           iconName: "figure.walk", hour: 9, minute: 30,
                                           weekdayMask: Weekdays.all)
        XCTAssertNotEqual(successor.id, original.id)
        XCTAssertEqual(successor.lineageID, original.lineageID)
        XCTAssertEqual(original.effectiveUntil, today)
        XCTAssertEqual(successor.effectiveFrom, today)
        XCTAssertEqual(successor.name, "Long walk")
        XCTAssertEqual(successor.hour, 9)
        // Only the successor is "current".
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Long walk"])
    }

    func testEditOfTaskCreatedTodayMutatesInPlace() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        let edited = try store.editTask(task, name: "Jog", category: .play, iconName: "figure.run",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertEqual(edited.id, task.id) // no successor: nothing historical to preserve
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Jog"])
    }

    func testEndTaskClosesHistoricalRowButDeletesSameDayRow() throws {
        let historical = try store.createTask(name: "Old", category: .care, iconName: "heart",
                                              hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                              from: day(-5))
        try store.endTask(historical)
        XCTAssertEqual(historical.effectiveUntil, today) // closed, not deleted

        let fresh = try store.createTask(name: "New", category: .care, iconName: "heart",
                                         hour: 9, minute: 0, weekdayMask: Weekdays.all)
        try store.endTask(fresh)
        let all = try context.fetch(RoutineTask.fetchRequest())
        XCTAssertFalse(all.contains { $0.name == "New" }) // genuinely deleted
        XCTAssertEqual(try store.currentTasks().count, 0)
    }

    func testAddOneOffCoversExactlyOneDay() throws {
        let target = day(2)
        let oneOff = try store.addOneOff(name: "Vet pickup", category: .health, iconName: "cross.case",
                                         hour: 15, minute: 0, on: target)
        XCTAssertTrue(oneOff.isOneOff)
        XCTAssertEqual(oneOff.effectiveFrom, target)
        XCTAssertEqual(oneOff.effectiveUntil, day(3))
        let weekday = calendar.component(.weekday, from: target)
        XCTAssertEqual(oneOff.weekdayMask, Weekdays.bit(for: weekday))
        // One-offs never appear in the template editor list.
        XCTAssertFalse(try store.currentTasks().contains { $0.isOneOff })
    }

    func testEmptyWhenNoPetExists() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.currentTasks().count, 0)
    }
}
