// ios/PetHomepageTests/RoutineStoreMealTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class RoutineStoreMealTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: RoutineStore!
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "meal-\(UUID().uuidString)")!)
        _ = try petStore.ensurePet()
        store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
    }

    private func mealSlot(named name: String = "Breakfast") throws -> RoutineTask {
        try store.createTask(name: name, category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all,
                             isMeal: true, mealAllotment: 2, mealUnit: "cups",
                             from: calendar.date(byAdding: .day, value: -1, to: today)!)
    }

    private func slot(for task: RoutineTask) throws -> RoutineSlot {
        try XCTUnwrap(try store.slots(for: today).first { $0.task.lineageID == task.lineageID })
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
    }

    func testInferMealFromName() throws {
        let dinner = try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                                          hour: 18, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertTrue(dinner.isMeal) // inferred
        let walk = try store.createTask(name: "Evening walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertFalse(walk.isMeal)
    }

    func testExplicitMealFlagWins() throws {
        // Feeding-named but explicitly not a meal.
        let t = try store.createTask(name: "Breakfast reminder note", category: .feeding,
                                     iconName: "fork.knife", hour: 7, minute: 0,
                                     weekdayMask: Weekdays.all, isMeal: false)
        XCTAssertFalse(t.isMeal)
    }

    func testMealWithoutAllotmentBehavesAsNormalCheckoff() throws {
        // isMeal true but allotment 0 → ordinary single check-off, completes normally.
        let t = try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                                     hour: 7, minute: 0, weekdayMask: Weekdays.all,
                                     isMeal: true, mealAllotment: 0)
        XCTAssertFalse(try slot(for: t).isMeal)
        _ = try store.checkOff(t, on: today, now: Date())
        XCTAssertTrue(try slot(for: t).isCompleted)
    }

    func testFeedingsAppendAndSum() throws {
        let meal = try mealSlot()
        _ = try store.logFeeding(meal, on: today, amount: 0.5)
        _ = try store.logFeeding(meal, on: today, amount: 0.75)
        XCTAssertEqual(try store.completions(of: meal, on: today).count, 2)
        XCTAssertEqual(try store.fedTotal(of: meal, on: today), 1.25, accuracy: 0.001)
        let s = try slot(for: meal)
        XCTAssertEqual(s.fedTotal, 1.25, accuracy: 0.001)
        XCTAssertFalse(s.isCompleted) // under 2 cups
        XCTAssertEqual(s.mealProgress, 0.625, accuracy: 0.001)
    }

    func testMealCompletesAtAllotmentAndReopensBelow() throws {
        let meal = try mealSlot()
        _ = try store.logFeeding(meal, on: today, amount: 1.5)
        XCTAssertFalse(try slot(for: meal).isCompleted)
        let last = try store.logFeeding(meal, on: today, amount: 0.5) // total 2.0
        XCTAssertTrue(try slot(for: meal).isCompleted)
        XCTAssertEqual(try slot(for: meal).mealProgress, 1.0, accuracy: 0.001)
        // Removing a feeding drops below allotment → reopens.
        try store.uncheck(last)
        XCTAssertFalse(try slot(for: meal).isCompleted)
    }

    func testFeedingCarriesUnit() throws {
        let meal = try mealSlot()
        let entry = try store.logFeeding(meal, on: today, amount: 1)
        XCTAssertEqual(entry.unit, "cups")
        XCTAssertEqual(entry.value, 1, accuracy: 0.001)
        XCTAssertEqual(entry.kind, .routine)
    }
}
