// ios/PetHomepageTests/DoseLogStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class DoseLogStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
    }

    private func makeMed() throws -> Medication {
        let t = Date(timeIntervalSince1970: 0)
        return try medStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                   scheduleTime: t, startedAt: t, refillDueAt: nil)
    }

    func testLogDoseLinksToMedication() throws {
        let store = DoseLogStore(context: context)
        let med = try makeMed()
        let when = Date(timeIntervalSince1970: 1_000)

        let log = try store.logDose(for: med, at: when)

        XCTAssertEqual(log.medication?.id, med.id)
        XCTAssertEqual(log.givenAt, when)
        XCTAssertNotNil(log.id)
    }

    func testLastGivenReturnsMostRecentDose() throws {
        let store = DoseLogStore(context: context)
        let med = try makeMed()
        try store.logDose(for: med, at: Date(timeIntervalSince1970: 1_000))
        try store.logDose(for: med, at: Date(timeIntervalSince1970: 3_000))
        try store.logDose(for: med, at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(try store.lastGiven(for: med), Date(timeIntervalSince1970: 3_000))
    }

    func testLastGivenIsNilWhenNoDosesLogged() throws {
        let store = DoseLogStore(context: context)
        let med = try makeMed()
        XCTAssertNil(try store.lastGiven(for: med))
    }

    func testDoseCountCountsOnlyThisMedicationsDoses() throws {
        let store = DoseLogStore(context: context)
        let medA = try makeMed()
        let t = Date(timeIntervalSince1970: 0)
        let medB = try medStore.create(drugName: "Zyrtec", dosage: "5mg", frequency: "daily",
                                       scheduleTime: t, startedAt: t, refillDueAt: nil)
        try store.logDose(for: medA, at: Date(timeIntervalSince1970: 1_000))
        try store.logDose(for: medA, at: Date(timeIntervalSince1970: 2_000))
        try store.logDose(for: medB, at: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(try store.doseCount(for: medA), 2)
        XCTAssertEqual(try store.doseCount(for: medB), 1)
    }
}
