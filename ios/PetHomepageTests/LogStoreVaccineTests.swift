// ios/PetHomepageTests/LogStoreVaccineTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class LogStoreVaccineTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = LogStore(context: context, petStore: petStore)
    }

    func testLogVaccineStampsKindAndFields() throws {
        let performed = Date(timeIntervalSince1970: 1_700_000_000)
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        let vax = try store.logVaccine(name: "Rabies", performedAt: performed, nextDueAt: due,
                                       lotNumber: "L7", administeredBy: "Dr. V")

        XCTAssertEqual(vax.kind, .vaccine)
        XCTAssertEqual(vax.title, "Rabies")
        XCTAssertEqual(vax.performedAt, performed)
        XCTAssertEqual(vax.nextDueAt, due)
        XCTAssertEqual(vax.lotNumber, "L7")
        XCTAssertEqual(vax.administeredBy, "Dr. V")
        XCTAssertEqual(vax.pet?.name, "Sandy")
    }

    func testVaccinesQueryOnlyReturnsVaccineKindNewestFirst() throws {
        _ = try store.createDiary(performedAt: Date(timeIntervalSince1970: 50), note: "not a vaccine")
        let older = try store.logVaccine(name: "DHPP", performedAt: Date(timeIntervalSince1970: 100),
                                         nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        let newer = try store.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 300),
                                         nextDueAt: nil, lotNumber: nil, administeredBy: nil)

        let vaccines = try store.vaccines()

        XCTAssertEqual(vaccines.map(\.id), [newer.id, older.id])
        XCTAssertEqual(try store.diaryEntries().count, 1)
    }

    func testUpdateVaccineMutatesInPlace() throws {
        let vax = try store.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
                                       nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        let newPerformed = Date(timeIntervalSince1970: 500)
        let newDue = Date(timeIntervalSince1970: 900)

        try store.updateVaccine(vax, name: "Rabies (booster)", performedAt: newPerformed,
                                nextDueAt: newDue, lotNumber: "L9", administeredBy: "Dr. Ruth")

        XCTAssertEqual(vax.title, "Rabies (booster)")
        XCTAssertEqual(vax.performedAt, newPerformed)
        XCTAssertEqual(vax.nextDueAt, newDue)
        XCTAssertEqual(vax.lotNumber, "L9")
        XCTAssertEqual(vax.administeredBy, "Dr. Ruth")
        XCTAssertEqual(try store.vaccines().count, 1)
    }

    func testEmptyWithoutPetReturnsNoVaccines() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let s = LogStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try s.vaccines().count, 0)
    }
}
