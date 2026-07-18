// ios/PetHomepageTests/RoutineStoreDayTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreDayTests: XCTestCase {
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

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testSlotsHonorWeekdayMask() throws {
        let weekdayToday = calendar.component(.weekday, from: today)
        let weekdayTomorrow = calendar.component(.weekday, from: day(1))
        try store.createTask(name: "Today only", category: .care, iconName: "heart",
                             hour: 8, minute: 0, weekdayMask: Weekdays.bit(for: weekdayToday),
                             from: day(-7))
        try store.createTask(name: "Tomorrow only", category: .care, iconName: "heart",
                             hour: 9, minute: 0, weekdayMask: Weekdays.bit(for: weekdayTomorrow),
                             from: day(-7))
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Today only"])
        XCTAssertEqual(try store.slots(for: day(1)).map(\.task.name), ["Tomorrow only"])
    }

    func testSlotsHonorEffectiveWindows() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                        from: day(-10))
        try store.editTask(task, name: "Long walk", category: .play, iconName: "figure.walk",
                           hour: 8, minute: 0, weekdayMask: Weekdays.all)
        // Yesterday computes against the old version; today against the successor.
        XCTAssertEqual(try store.slots(for: day(-1)).map(\.task.name), ["Walk"])
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Long walk"])
        // Before the task ever existed: nothing.
        XCTAssertEqual(try store.slots(for: day(-11)).count, 0)
    }

    func testOneOffAppearsOnlyOnItsDay() throws {
        try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                             hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.addOneOff(name: "Vet pickup", category: .health, iconName: "cross.case",
                            hour: 15, minute: 0, on: day(2))
        XCTAssertEqual(try store.slots(for: day(2)).map(\.task.name), ["Walk", "Vet pickup"])
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Walk"])
        XCTAssertEqual(try store.slots(for: day(3)).map(\.task.name), ["Walk"])
    }

    func testSkipAndUnskipOverlay() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.skip(task, on: today)
        var slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertTrue(slot.isSkipped)
        // Skips are per-day: yesterday untouched.
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: day(-1)).first).isSkipped)
        // Skipping twice is a no-op (idempotent), unskip removes.
        try store.skip(task, on: today)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 1)
        try store.unskip(task, on: today)
        slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertFalse(slot.isSkipped)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 0)
    }

    func testSlotsSortByTime() throws {
        try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                             hour: 18, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Breakfast", "Dinner"])
    }

    func testSlotsEmptyWithoutPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.slots(for: Date()).count, 0)
    }
}
