// ios/PetHomepageTests/PetProfileViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetProfileViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testSaveCreatesPetWhenNoneExists() throws {
        let store = PetStore(context: context)
        let vm = PetProfileViewModel(store: store)
        vm.name = "Sandy"
        vm.species = "dog"

        try vm.save()

        XCTAssertEqual(try store.currentPet()?.name, "Sandy")
        XCTAssertTrue(vm.isSaved)
    }

    func testInitLoadsExistingPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Max", species: "dog")

        let vm = PetProfileViewModel(store: store)

        XCTAssertEqual(vm.name, "Max")
    }

    func testSaveUpdatesExistingPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Max", species: "dog")
        let vm = PetProfileViewModel(store: store)
        vm.name = "Maximilian"

        try vm.save()

        XCTAssertEqual(try store.currentPet()?.name, "Maximilian")
    }
}
