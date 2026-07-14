// ios/PetHomepageTests/RoutineStoreWalkFlagTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class RoutineStoreWalkFlagTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: RoutineStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "walk-flag-\(UUID().uuidString)")!)
        _ = try petStore.ensurePet()
        store = RoutineStore(context: context, petStore: petStore, calendar: .current)
    }

    func testCreateInfersWalkFromName() throws {
        let walk = try store.createTask(name: "Evening walk", category: .other,
                                        iconName: "pawprint", hour: 17, minute: 30,
                                        weekdayMask: Weekdays.all)
        XCTAssertTrue(walk.isWalk)
        let breakfast = try store.createTask(name: "Breakfast", category: .feeding,
                                             iconName: "fork.knife", hour: 7, minute: 0,
                                             weekdayMask: Weekdays.all)
        XCTAssertFalse(breakfast.isWalk)
    }

    func testExplicitFlagBeatsInference() throws {
        // "walk" in the name but deliberately opted out (e.g. "walk-in vet hours").
        let task = try store.createTask(name: "Walk-in vet hours", category: .health,
                                        iconName: "cross.case", hour: 10, minute: 0,
                                        weekdayMask: Weekdays.all, isWalk: false)
        XCTAssertFalse(task.isWalk)
    }

    func testVersionedEditCarriesFlagToSuccessor() throws {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let task = try store.createTask(name: "Evening walk", category: .training,
                                        iconName: "figure.walk", hour: 17, minute: 30,
                                        weekdayMask: Weekdays.all, from: weekAgo)
        XCTAssertTrue(task.isWalk)
        // Edit that spawns a successor (row has history): flag must carry over.
        let successor = try store.editTask(task, name: "Evening stroll", category: .training,
                                           iconName: "figure.walk", hour: 18, minute: 0,
                                           weekdayMask: Weekdays.all)
        XCTAssertNotEqual(successor.id, task.id)
        XCTAssertTrue(successor.isWalk)
        // Explicit opt-out on a later edit is respected.
        let optedOut = try store.editTask(successor, name: "Evening stroll", category: .training,
                                          iconName: "figure.walk", hour: 18, minute: 0,
                                          weekdayMask: Weekdays.all, isWalk: false)
        XCTAssertFalse(optedOut.isWalk)
    }

    func testBackfillMarksLegacyWalkShapedRows() throws {
        // Simulate pre-flag rows: explicit false at creation.
        let named = try store.createTask(name: "Morning walk", category: .other,
                                         iconName: "pawprint", hour: 8, minute: 0,
                                         weekdayMask: Weekdays.all, isWalk: false)
        let shaped = try store.createTask(name: "Fetch", category: .play,
                                          iconName: "figure.walk", hour: 16, minute: 0,
                                          weekdayMask: Weekdays.all, isWalk: false)
        let breakfast = try store.createTask(name: "Breakfast", category: .feeding,
                                             iconName: "fork.knife", hour: 7, minute: 0,
                                             weekdayMask: Weekdays.all, isWalk: false)

        try store.backfillWalkFlags()

        XCTAssertTrue(named.isWalk)
        XCTAssertTrue(shaped.isWalk)
        XCTAssertFalse(breakfast.isWalk)
    }
}
