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

    func testLogStampsNextDueFromInterval() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let start = Date(timeIntervalSince1970: 0)
        let log = try store.log(type: type, performedAt: start, note: "clean pup", intervalDays: 30)
        XCTAssertEqual(log.pet?.name, "Sandy")
        XCTAssertEqual(log.note, "clean pup")
        XCTAssertEqual(log.nextDueAt, Calendar.current.date(byAdding: .day, value: 30, to: start))
    }

    func testLogWithZeroIntervalHasNoNextDue() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try store.log(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        XCTAssertNil(log.nextDueAt)
    }

    func testLatestLogReturnsMostRecentOfType() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 1_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 3_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 2_000), note: nil, intervalDays: 0)
        XCTAssertEqual(try store.latestLog(of: type)?.performedAt, Date(timeIntervalSince1970: 3_000))
    }

    func testLogsAreNewestFirst() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 1_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 2_000), note: nil, intervalDays: 0)
        XCTAssertEqual(try store.logs().map(\.performedAt),
                       [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
    }

    func testDeleteRemovesLog() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try store.log(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        try store.delete(log)
        XCTAssertEqual(try store.logs().count, 0)
    }

    func testEmptyWhenNoPetExists() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = ActivityStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.types().count, 0)
        XCTAssertEqual(try emptyStore.logs().count, 0)
    }
}
