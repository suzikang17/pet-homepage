// ios/PetHomepageTests/ActivityStoreSeedingTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityStoreSeedingTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: ActivityStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = ActivityStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testSeedingCreatesDefaultsOnce() throws {
        try store.seedDefaultsIfNeeded()
        let firstCount = try store.types().count
        XCTAssertEqual(firstCount, ActivityStore.defaultSeeds.count)
        XCTAssertTrue(try store.types().contains { $0.name == "Bath" })

        try store.seedDefaultsIfNeeded()
        XCTAssertEqual(try store.types().count, firstCount, "second seed must add nothing")
    }

    func testSeedingSkipsNamesThatAlreadyExist() throws {
        try store.createType(name: "Bath", category: .play, iconName: "tennisball", defaultIntervalDays: 0)
        try store.seedDefaultsIfNeeded()
        let baths = try store.types(includeArchived: true).filter { $0.name == "Bath" }
        XCTAssertEqual(baths.count, 1, "must not duplicate an existing 'Bath'")
        XCTAssertEqual(baths.first?.category, .play, "must not overwrite the user's existing type")
    }

    func testSeedingDoesNothingWithoutAPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = ActivityStore(context: ctx, petStore: PetStore(context: ctx))
        try emptyStore.seedDefaultsIfNeeded()
        XCTAssertEqual(try emptyStore.types(includeArchived: true).count, 0)
    }
}
