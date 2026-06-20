// ios/PetHomepageTests/VaccinationStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VaccinationStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: VaccinationStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = VaccinationStore(context: context, petStore: petStore)
    }

    func testCreateAndFetchScopedToCurrentPet() throws {
        try store.create(vaccineName: "Rabies",
                         administeredAt: Date(timeIntervalSince1970: 1_700_000_000),
                         nextDueAt: nil, lotNumber: "L123", administeredBy: "Dr. Vet")

        let all = try store.vaccinations()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.vaccineName, "Rabies")
        XCTAssertEqual(all.first?.lotNumber, "L123")
        XCTAssertEqual(all.first?.administeredBy, "Dr. Vet")
    }

    func testVaccinationsSortedByAdministeredAtDescending() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try store.create(vaccineName: "Rabies", administeredAt: older, nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        try store.create(vaccineName: "DHPP", administeredAt: newer, nextDueAt: nil, lotNumber: nil, administeredBy: nil)

        let all = try store.vaccinations()
        XCTAssertEqual(all.map(\.vaccineName), ["DHPP", "Rabies"])
    }

    func testLastGivenReturnsMostRecentForName() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try store.create(vaccineName: "Rabies", administeredAt: older, nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        try store.create(vaccineName: "Rabies", administeredAt: newer, nextDueAt: nil, lotNumber: nil, administeredBy: nil)

        XCTAssertEqual(try store.lastGiven(vaccineName: "Rabies"), newer)
    }

    func testNextDueReturnsEarliestDueForName() throws {
        let due1 = Date(timeIntervalSince1970: 1_800_000_000)
        let due2 = Date(timeIntervalSince1970: 1_900_000_000)
        try store.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1), nextDueAt: due2, lotNumber: nil, administeredBy: nil)
        try store.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 2), nextDueAt: due1, lotNumber: nil, administeredBy: nil)

        XCTAssertEqual(try store.nextDue(vaccineName: "Rabies"), due1)
    }

    func testUpdateAndDelete() throws {
        let vax = try store.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1), nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        try store.update(vax, vaccineName: "Rabies 3yr", administeredAt: Date(timeIntervalSince1970: 2), nextDueAt: nil, lotNumber: "L9", administeredBy: "Dr. B")
        XCTAssertEqual(try store.vaccinations().first?.vaccineName, "Rabies 3yr")
        XCTAssertEqual(try store.vaccinations().first?.lotNumber, "L9")

        try store.delete(vax)
        XCTAssertTrue(try store.vaccinations().isEmpty)
    }
}
