// ios/PetHomepageTests/LogStoreVetTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class LogStoreVetTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = LogStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testLogVetVisitStampsKindAndFields() throws {
        let occurred = Date(timeIntervalSince1970: 1_700_000_000)
        let nextVisit = Date(timeIntervalSince1970: 1_900_000_000)
        let visit = try store.logVetVisit(occurredAt: occurred, clinicName: "Paws Clinic",
                                          vetName: "Dr. Vet", reason: "Checkup",
                                          diagnosis: "Healthy", treatmentNotes: "None",
                                          nextVisitDate: nextVisit)

        XCTAssertEqual(visit.kind, .vet)
        XCTAssertEqual(visit.title, "Checkup")
        XCTAssertEqual(visit.performedAt, occurred)
        XCTAssertEqual(visit.clinicName, "Paws Clinic")
        XCTAssertEqual(visit.vetName, "Dr. Vet")
        XCTAssertEqual(visit.diagnosis, "Healthy")
        XCTAssertEqual(visit.treatmentNotes, "None")
        XCTAssertEqual(visit.nextDueAt, nextVisit)
        XCTAssertEqual(visit.pet?.name, "Sandy")
    }

    func testVetVisitsQueryOnlyReturnsVetKindNewestFirst() throws {
        _ = try store.createDiary(performedAt: Date(timeIntervalSince1970: 50), note: "not a visit")
        let older = try store.logVetVisit(occurredAt: Date(timeIntervalSince1970: 100),
                                          clinicName: "A", vetName: nil, reason: nil,
                                          diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let newer = try store.logVetVisit(occurredAt: Date(timeIntervalSince1970: 300),
                                          clinicName: "B", vetName: nil, reason: nil,
                                          diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)

        let visits = try store.vetVisits()

        XCTAssertEqual(visits.map(\.id), [newer.id, older.id])
        XCTAssertEqual(try store.diaryEntries().count, 1)
    }

    func testUpdateVetVisitMutatesInPlace() throws {
        let visit = try store.logVetVisit(occurredAt: Date(timeIntervalSince1970: 1),
                                          clinicName: "A", vetName: nil, reason: nil,
                                          diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let newOccurred = Date(timeIntervalSince1970: 500)
        let newNextVisit = Date(timeIntervalSince1970: 900)

        try store.updateVetVisit(visit, occurredAt: newOccurred, clinicName: "A2",
                                 vetName: "Dr. C", reason: "Limp", diagnosis: "Sprain",
                                 treatmentNotes: "Rest", nextVisitDate: newNextVisit)

        XCTAssertEqual(visit.clinicName, "A2")
        XCTAssertEqual(visit.vetName, "Dr. C")
        XCTAssertEqual(visit.title, "Limp")
        XCTAssertEqual(visit.diagnosis, "Sprain")
        XCTAssertEqual(visit.treatmentNotes, "Rest")
        XCTAssertEqual(visit.performedAt, newOccurred)
        XCTAssertEqual(visit.nextDueAt, newNextVisit)
        XCTAssertEqual(try store.vetVisits().count, 1)
    }

    func testMostRecentVisitDateReturnsNewestPerformedAt() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try store.logVetVisit(occurredAt: older, clinicName: nil, vetName: nil, reason: nil,
                              diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.logVetVisit(occurredAt: newer, clinicName: nil, vetName: nil, reason: nil,
                              diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)

        XCTAssertEqual(try store.mostRecentVisitDate(), newer)
    }

    func testMostRecentVisitDateIsNilWhenNoVisits() throws {
        XCTAssertNil(try store.mostRecentVisitDate())
    }

    func testEmptyWithoutPetReturnsNoVisits() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let s = LogStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try s.vetVisits().count, 0)
    }
}
