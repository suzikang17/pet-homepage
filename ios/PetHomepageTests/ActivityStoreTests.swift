// ios/PetHomepageTests/ActivityStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityStoreTests: XCTestCase {
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

    func testCreateTypeIsListedAndScopedToPet() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        XCTAssertNotNil(type.id)
        let types = try store.types()
        XCTAssertEqual(types.map(\.name), ["Bath"])
        XCTAssertEqual(types.first?.pet?.name, "Sandy")
    }

    func testArchivedTypesAreHiddenByDefault() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        try store.archiveType(type)
        XCTAssertEqual(try store.types().count, 0)
        XCTAssertEqual(try store.types(includeArchived: true).count, 1)
    }

    func testReminderTimePersistsOnCreateAndUpdate() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower",
                                        defaultIntervalDays: 30, reminderHour: 18, reminderMinute: 30)
        let fetched = try store.types().first
        XCTAssertEqual(fetched?.reminderHour, 18)
        XCTAssertEqual(fetched?.reminderMinute, 30)

        try store.updateType(type, name: "Bath", category: .care, iconName: "shower",
                             defaultIntervalDays: 30, reminderHour: 7, reminderMinute: 15)
        let updated = try store.types().first
        XCTAssertEqual(updated?.reminderHour, 7)
        XCTAssertEqual(updated?.reminderMinute, 15)
    }

    func testReminderTimeDefaultsToNineWhenUnset() throws {
        _ = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let fetched = try store.types().first
        XCTAssertEqual(fetched?.reminderHour, 9)
        XCTAssertEqual(fetched?.reminderMinute, 0)
    }

    func testEmptyWhenNoPetExists() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = ActivityStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.types().count, 0)
    }
}
