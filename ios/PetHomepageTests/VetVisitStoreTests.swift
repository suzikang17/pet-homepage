// ios/PetHomepageTests/VetVisitStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VetVisitStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: VetVisitStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = VetVisitStore(context: context, petStore: petStore)
    }

    func testCreateAndFetchScopedToCurrentPet() throws {
        try store.create(occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                         clinicName: "Paws Clinic", vetName: "Dr. Vet",
                         reason: "Checkup", diagnosis: "Healthy",
                         treatmentNotes: "None", nextVisitDate: nil)

        let all = try store.visits()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.clinicName, "Paws Clinic")
        XCTAssertEqual(all.first?.reason, "Checkup")
    }

    func testVisitsSortedByOccurredAtDescending() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try store.create(occurredAt: older, clinicName: "A", vetName: nil, reason: nil, diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.create(occurredAt: newer, clinicName: "B", vetName: nil, reason: nil, diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)

        XCTAssertEqual(try store.visits().map(\.clinicName), ["B", "A"])
    }

    func testMostRecentVisitDate() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try store.create(occurredAt: older, clinicName: nil, vetName: nil, reason: nil, diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.create(occurredAt: newer, clinicName: nil, vetName: nil, reason: nil, diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)

        XCTAssertEqual(try store.mostRecentVisitDate(), newer)
    }

    func testMostRecentVisitDateIsNilWhenNoVisits() throws {
        XCTAssertNil(try store.mostRecentVisitDate())
    }

    func testUpdateAndDelete() throws {
        let visit = try store.create(occurredAt: Date(timeIntervalSince1970: 1),
                                     clinicName: "A", vetName: nil, reason: nil,
                                     diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.update(visit, occurredAt: Date(timeIntervalSince1970: 2),
                         clinicName: "A2", vetName: "Dr. C", reason: "Limp",
                         diagnosis: "Sprain", treatmentNotes: "Rest", nextVisitDate: nil)
        XCTAssertEqual(try store.visits().first?.clinicName, "A2")
        XCTAssertEqual(try store.visits().first?.diagnosis, "Sprain")

        try store.delete(visit)
        XCTAssertTrue(try store.visits().isEmpty)
    }
}
