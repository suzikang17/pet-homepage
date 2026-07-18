// ios/PetHomepageTests/VetRecommendationStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VetRecommendationStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!
    private var store: VetRecommendationStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        store = VetRecommendationStore(context: context)
    }

    override func tearDownWithError() throws {
        context = nil
        logStore = nil
        store = nil
    }

    func testCreateLinkedToVisitAndFetch() throws {
        let visit = try logStore.logVetVisit(occurredAt: Date(timeIntervalSince1970: 1),
                                             clinicName: nil, vetName: nil, reason: nil,
                                             diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.create(text: "Switch to senior food", date: Date(timeIntervalSince1970: 2), logEntry: visit)

        let recs = try store.recommendations(for: visit)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.text, "Switch to senior food")
        XCTAssertEqual(recs.first?.logEntry?.id, visit.id)
    }

    func testRecommendationsSortedByDateDescending() throws {
        let visit = try logStore.logVetVisit(occurredAt: Date(timeIntervalSince1970: 1),
                                             clinicName: nil, vetName: nil, reason: nil,
                                             diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.create(text: "older", date: Date(timeIntervalSince1970: 100), logEntry: visit)
        try store.create(text: "newer", date: Date(timeIntervalSince1970: 200), logEntry: visit)

        XCTAssertEqual(try store.recommendations(for: visit).map(\.text), ["newer", "older"])
    }

    func testUnlinkedRecommendationsAreFetchable() throws {
        try store.create(text: "Standalone advice", date: Date(timeIntervalSince1970: 5), logEntry: nil)

        let unlinked = try store.unlinkedRecommendations()
        XCTAssertEqual(unlinked.count, 1)
        XCTAssertEqual(unlinked.first?.text, "Standalone advice")
        XCTAssertNil(unlinked.first?.logEntry)
    }

    func testUpdateAndDelete() throws {
        let rec = try store.create(text: "old", date: Date(timeIntervalSince1970: 1), logEntry: nil)
        try store.update(rec, text: "new", date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try store.unlinkedRecommendations().first?.text, "new")

        try store.delete(rec)
        XCTAssertTrue(try store.unlinkedRecommendations().isEmpty)
    }
}
