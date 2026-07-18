// ios/PetHomepageTests/MedicationStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class MedicationStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
    }

    func testCreateMedicationWithoutAPetCreatesADefaultPetAndSaves() throws {
        // Fresh context with NO pet — simulates adding a med before the user sets up their pet.
        let freshContext = PersistenceController(inMemory: true).container.viewContext
        let freshPetStore = PetStore(context: freshContext)
        XCTAssertNil(try freshPetStore.currentPet())

        let store = MedicationStore(context: freshContext, petStore: freshPetStore)
        try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                         scheduleTime: Date(), startedAt: Date(), endedAt: nil, refillDueAt: nil)

        let meds = try store.medications()
        XCTAssertEqual(meds.count, 1, "med must save + list even with no pre-existing pet")
        XCTAssertEqual(meds.first?.drugName, "Apoquel")
        XCTAssertEqual(meds.first?.pet?.name, "Your pet", "a default pet should have been created")
    }

    func testCreateMedicationIsScopedToCurrentPet() throws {
        let store = MedicationStore(context: context, petStore: petStore)
        let scheduleTime = Date(timeIntervalSince1970: 0)
        try store.create(drugName: "Heartgard",
                         dosage: "1 chew",
                         frequency: "monthly",
                         scheduleTime: scheduleTime,
                         startedAt: scheduleTime,
                         refillDueAt: nil)

        let meds = try store.medications()
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.drugName, "Heartgard")
        XCTAssertEqual(meds.first?.pet?.name, "Sandy")
        XCTAssertNotNil(meds.first?.id)
    }

    func testMedicationsAreSortedByDrugName() throws {
        let store = MedicationStore(context: context, petStore: petStore)
        let t = Date(timeIntervalSince1970: 0)
        try store.create(drugName: "Zyrtec", dosage: "5mg", frequency: "daily", scheduleTime: t, startedAt: t, refillDueAt: nil)
        try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: t, startedAt: t, refillDueAt: nil)

        let names = try store.medications().map(\.drugName)
        XCTAssertEqual(names, ["Apoquel", "Zyrtec"])
    }

    func testUpdateChangesFields() throws {
        let store = MedicationStore(context: context, petStore: petStore)
        let t = Date(timeIntervalSince1970: 0)
        let med = try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: t, startedAt: t, refillDueAt: nil)

        let later = Date(timeIntervalSince1970: 86_400)
        try store.update(med, drugName: "Apoquel", dosage: "8mg", frequency: "twice daily",
                         scheduleTime: t, startedAt: t, endedAt: nil, refillDueAt: later)

        let fetched = try store.medications().first
        XCTAssertEqual(fetched?.dosage, "8mg")
        XCTAssertEqual(fetched?.frequency, "twice daily")
        XCTAssertEqual(fetched?.refillDueAt, later)
    }

    func testDeleteRemovesMedication() throws {
        let store = MedicationStore(context: context, petStore: petStore)
        let t = Date(timeIntervalSince1970: 0)
        let med = try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: t, startedAt: t, refillDueAt: nil)

        try store.delete(med)

        XCTAssertEqual(try store.medications().count, 0)
    }

    func testMedicationsIsEmptyWhenNoPetExists() throws {
        let emptyContext = PersistenceController(inMemory: true).container.viewContext
        let store = MedicationStore(context: emptyContext, petStore: PetStore(context: emptyContext))
        XCTAssertEqual(try store.medications().count, 0)
    }
}
