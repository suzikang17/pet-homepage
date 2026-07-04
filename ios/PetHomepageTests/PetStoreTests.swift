// ios/PetHomepageTests/PetStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var scratchDefaults: UserDefaults!
    private var scratchSuiteName: String!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        scratchSuiteName = "PetStoreTests.\(UUID().uuidString)"
        scratchDefaults = UserDefaults(suiteName: scratchSuiteName)
    }

    override func tearDownWithError() throws {
        scratchDefaults.removePersistentDomain(forName: scratchSuiteName)
        scratchDefaults = nil
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

    func testSetSpeciesPersistsAndCreatesPetIfNeeded() throws {
        let store = PetStore(context: context)
        try store.setSpecies("cat", defaultName: "Whiskers")
        XCTAssertEqual(try store.currentPet()?.species, "cat")
        XCTAssertEqual(try store.currentPet()?.name, "Whiskers")

        try store.setSpecies("other")
        XCTAssertEqual(try store.currentPet()?.species, "other")
    }

    func testSetPhotoCreatesPetWhenNoneExists() throws {
        let store = PetStore(context: context)
        XCTAssertNil(try store.currentPet())

        try store.setPhoto(Data([0xAB]), defaultName: "Buddy", defaultSpecies: "cat")

        let pet = try store.currentPet()
        XCTAssertEqual(pet?.name, "Buddy")
        XCTAssertEqual(pet?.photoData, Data([0xAB]))
    }

    // MARK: - Multi-pet: active-pet mechanics

    func testPetsReturnsAllPetsSortedByName() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        try store.createPet(name: "Zorro", species: "cat")
        try store.createPet(name: "Milo", species: "dog")
        try store.createPet(name: "Ana", species: "rabbit")

        let names = try store.pets().map(\.name)

        XCTAssertEqual(names, ["Ana", "Milo", "Zorro"])
    }

    func testSetActivePetPersistsAndCurrentPetReturnsIt() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        let milo = try store.createPet(name: "Milo", species: "dog")
        let zorro = try store.createPet(name: "Zorro", species: "cat")

        // Default (no explicit active pet yet) falls back to the first pet.
        XCTAssertEqual(try store.currentPet()?.id, milo.id)

        store.setActivePet(zorro)
        XCTAssertEqual(try store.currentPet()?.id, zorro.id)

        store.setActivePet(milo)
        XCTAssertEqual(try store.currentPet()?.id, milo.id)
    }

    func testUnknownStoredActivePetIDFallsBackToFirstPet() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        let onlyPet = try store.createPet(name: "Sandy", species: "dog")
        scratchDefaults.set(UUID().uuidString, forKey: "activePetID") // never-created id

        XCTAssertEqual(try store.currentPet()?.id, onlyPet.id)
    }

    func testRecordsCreatedAfterSwitchAttachToNewActivePetAndScopedQueriesFilter() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        let petA = try store.createPet(name: "Ana", species: "rabbit")
        let petB = try store.createPet(name: "Milo", species: "dog")
        let logStore = LogStore(context: context, petStore: store)

        store.setActivePet(petA)
        try logStore.createDiary(note: "A note")

        store.setActivePet(petB)
        try logStore.createDiary(note: "B note")

        let bEntries = try logStore.diaryEntries()
        XCTAssertEqual(bEntries.map(\.note), ["B note"])
        XCTAssertEqual(bEntries.first?.pet?.id, petB.id)

        store.setActivePet(petA)
        let aEntries = try logStore.diaryEntries()
        XCTAssertEqual(aEntries.map(\.note), ["A note"])
        XCTAssertEqual(aEntries.first?.pet?.id, petA.id)
    }
}
