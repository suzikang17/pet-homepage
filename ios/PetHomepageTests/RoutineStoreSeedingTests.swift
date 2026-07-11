// ios/PetHomepageTests/RoutineStoreSeedingTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreSeedingTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
    }

    func testSeedsDefaultRoutineOnce() throws {
        try store.seedDefaultsIfNeeded()
        let names = try store.currentTasks().map(\.name)
        XCTAssertEqual(Set(names), ["Breakfast", "Morning walk", "Training", "Dinner", "Wind down"])
        // Training demonstrates day-of-week from minute one: Tue + Thu only.
        let training = try XCTUnwrap(try store.currentTasks().first { $0.name == "Training" })
        XCTAssertEqual(training.weekdayMask, Weekdays.mask(of: [3, 5]))
        // Idempotent.
        try store.seedDefaultsIfNeeded()
        XCTAssertEqual(try store.currentTasks().count, 5)
    }

    func testSeedingRespectsDeletedSeeds() throws {
        try store.seedDefaultsIfNeeded()
        let training = try XCTUnwrap(try store.currentTasks().first { $0.name == "Training" })
        // Make it historical so endTask closes (not deletes) the row, then re-seed.
        training.effectiveFrom = Calendar.current.date(byAdding: .day, value: -5,
                                                       to: Calendar.current.startOfDay(for: Date()))!
        try context.save()
        try store.endTask(training)
        try store.seedDefaultsIfNeeded()
        // The closed row still exists, so the seed must NOT resurrect Training.
        XCTAssertFalse(try store.currentTasks().contains { $0.name == "Training" })
    }

    func testSeedingNoOpWithoutPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        try emptyStore.seedDefaultsIfNeeded()
        XCTAssertEqual(try ctx.fetch(RoutineTask.fetchRequest()).count, 0)
    }
}
