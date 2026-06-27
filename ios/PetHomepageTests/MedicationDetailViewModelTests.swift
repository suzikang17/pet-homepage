// ios/PetHomepageTests/MedicationDetailViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class MedicationDetailViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: MedicationStore!
    private var doseLogStore: DoseLogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = MedicationStore(context: context, petStore: petStore)
        doseLogStore = DoseLogStore(context: context)
    }

    private func makeMed() throws -> Medication {
        try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                         scheduleTime: Date(), startedAt: Date(), endedAt: nil, refillDueAt: nil)
    }

    func testLogDoseAppendsAndOrdersNewestFirst() throws {
        let vm = MedicationDetailViewModel(medication: try makeMed(), doseLogStore: doseLogStore)
        XCTAssertEqual(vm.doseCount, 0)
        XCTAssertNil(vm.lastGiven)

        vm.logDose(at: Date(timeIntervalSince1970: 100))
        vm.logDose(at: Date(timeIntervalSince1970: 500))

        XCTAssertEqual(vm.doseCount, 2)
        XCTAssertEqual(vm.lastGiven, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(vm.doses.first?.givenAt, Date(timeIntervalSince1970: 500))
    }

    func testDeleteDoseRemovesIt() throws {
        let vm = MedicationDetailViewModel(medication: try makeMed(), doseLogStore: doseLogStore)
        vm.logDose(at: Date(timeIntervalSince1970: 100))
        let dose = try XCTUnwrap(vm.doses.first)

        vm.deleteDose(dose)

        XCTAssertEqual(vm.doseCount, 0)
        XCTAssertNil(vm.lastGiven)
    }
}
