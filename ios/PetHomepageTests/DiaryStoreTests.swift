// ios/PetHomepageTests/DiaryStoreTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class DiaryStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: DiaryStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        store = DiaryStore(context: context, petStore: petStore)
    }

    func testCreateEntryListsNewestFirstAndScopesToPet() throws {
        try store.createEntry(date: Date(timeIntervalSince1970: 100), note: "Older")
        try store.createEntry(date: Date(timeIntervalSince1970: 500), note: "Newer")

        let entries = try store.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.note, "Newer")
        XCTAssertEqual(entries.first?.pet?.name, "Your pet")
    }

    func testAddPhotoLinksToEntryAndAppearsInAllPhotos() throws {
        let entry = try store.createEntry(date: Date(), note: "Walk")
        try store.addPhoto(to: entry, imageData: Data([0x1, 0x2, 0x3]))

        XCTAssertEqual(entry.photoArray.count, 1)
        XCTAssertEqual(try store.allPhotos().count, 1)
        XCTAssertEqual(try store.allPhotos().first?.diaryEntry, entry)
    }

    func testDeleteEntryCascadesItsPhotos() throws {
        let entry = try store.createEntry(date: Date(), note: "Walk")
        try store.addPhoto(to: entry, imageData: Data([0x1]))
        XCTAssertEqual(try store.allPhotos().count, 1)

        try store.deleteEntry(entry)

        XCTAssertTrue(try store.entries().isEmpty)
        XCTAssertTrue(try store.allPhotos().isEmpty)
    }
}
