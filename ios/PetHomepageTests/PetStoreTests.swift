// ios/PetHomepageTests/PetStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testCreatePetIsRetrievableAsCurrentPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Sandy", species: "dog")

        let pet = try store.currentPet()
        XCTAssertEqual(pet?.name, "Sandy")
        XCTAssertEqual(pet?.species, "dog")
        XCTAssertNotNil(pet?.id)
    }

    func testUpdateChangesNameAndSpecies() throws {
        let store = PetStore(context: context)
        let pet = try store.createPet(name: "Sandy", species: "dog")

        try store.update(pet, name: "Sandy B.", species: "dog")

        XCTAssertEqual(try store.currentPet()?.name, "Sandy B.")
    }

    func testCurrentPetIsNilWhenNoneExists() throws {
        let store = PetStore(context: context)
        XCTAssertNil(try store.currentPet())
    }
}
