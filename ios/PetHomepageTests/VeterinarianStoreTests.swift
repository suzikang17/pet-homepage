// ios/PetHomepageTests/VeterinarianStoreTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class VeterinarianStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        store = VeterinarianStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testCreateAndListScopedToPet() throws {
        try store.create(name: "Dr. Ruth", clinic: "Maple Vet", phone: "555-1234")
        let vets = try store.veterinarians()
        XCTAssertEqual(vets.count, 1)
        XCTAssertEqual(vets.first?.name, "Dr. Ruth")
        XCTAssertEqual(vets.first?.clinic, "Maple Vet")
        XCTAssertEqual(vets.first?.pet?.name, "Your pet", "ensurePet should create a default pet")
    }

    func testUpdateAndDelete() throws {
        let vet = try store.create(name: "Dr. A")
        try store.update(vet, name: "Dr. B", clinic: "Clinic", phone: nil,
                         email: nil, address: nil, website: nil, notes: nil)
        XCTAssertEqual(try store.veterinarians().first?.name, "Dr. B")

        try store.delete(vet)
        XCTAssertTrue(try store.veterinarians().isEmpty)
    }

    func testAttachToMedicationPopulatesInverse() throws {
        let vet = try store.create(name: "Dr. Ruth")
        let medStore = MedicationStore(context: context, petStore: petStore)
        let med = try medStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                      scheduleTime: Date(), nextReminderAt: Date(), endedAt: nil, refillDueAt: nil)
        med.veterinarian = vet
        try context.save()

        XCTAssertEqual(med.veterinarian?.name, "Dr. Ruth")
        XCTAssertEqual(vet.medications?.count, 1, "inverse relationship should populate")
    }
}
