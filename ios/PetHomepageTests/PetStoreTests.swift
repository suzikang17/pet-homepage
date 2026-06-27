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

    func testSetPhotoPersistsOnExistingPetAndCanBeCleared() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Sandy", species: "dog")
        let data = Data([0x1, 0x2, 0x3, 0x4])

        try store.setPhoto(data)
        XCTAssertEqual(try store.currentPet()?.photoData, data)

        try store.setPhoto(nil)
        XCTAssertNil(try store.currentPet()?.photoData)
    }

    func testSetPhotoCreatesPetWhenNoneExists() throws {
        let store = PetStore(context: context)
        XCTAssertNil(try store.currentPet())

        try store.setPhoto(Data([0xAB]), defaultName: "Buddy", defaultSpecies: "cat")

        let pet = try store.currentPet()
        XCTAssertEqual(pet?.name, "Buddy")
        XCTAssertEqual(pet?.photoData, Data([0xAB]))
    }
}
