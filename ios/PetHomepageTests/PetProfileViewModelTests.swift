// ios/PetHomepageTests/PetProfileViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetProfileViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var scratchDefaults: UserDefaults!
    private var scratchSuiteName: String!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        scratchSuiteName = "PetProfileViewModelTests.\(UUID().uuidString)"
        scratchDefaults = UserDefaults(suiteName: scratchSuiteName)
    }

    override func tearDownWithError() throws {
        scratchDefaults.removePersistentDomain(forName: scratchSuiteName)
        scratchDefaults = nil
        context = nil
        scratchSuiteName = nil
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

    // MARK: - Multi-pet: switcher

    func testSwitchToChangesCurrentPetAndScopedQueries() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        let ana = try store.createPet(name: "Ana", species: "rabbit")
        let milo = try store.createPet(name: "Milo", species: "dog")
        let logStore = LogStore(context: context, petStore: store)
        let vm = PetProfileViewModel(store: store)

        // Defaults to the first pet (Ana) before any explicit switch.
        XCTAssertEqual(vm.activePetID, ana.id)
        try logStore.createDiary(note: "Ana's note")

        vm.switchTo(milo)
        vm.reload()

        XCTAssertEqual(vm.activePetID, milo.id)
        XCTAssertEqual(vm.name, "Milo")
        XCTAssertEqual(try store.currentPet()?.id, milo.id)

        try logStore.createDiary(note: "Milo's note")
        let miloEntries = try logStore.diaryEntries()
        XCTAssertEqual(miloEntries.map(\.note), ["Milo's note"])

        vm.switchTo(ana)
        vm.reload()
        let anaEntries = try logStore.diaryEntries()
        XCTAssertEqual(anaEntries.map(\.note), ["Ana's note"])
    }

    func testAddPetCreatesActivatesAndReloadsPetsList() throws {
        let store = PetStore(context: context, defaults: scratchDefaults)
        try store.createPet(name: "Ana", species: "rabbit")
        let vm = PetProfileViewModel(store: store)
        vm.reload()
        XCTAssertEqual(vm.pets.map(\.name), ["Ana"])

        let bella = vm.addPet(name: "Bella", species: "cat")
        vm.reload()

        XCTAssertNotNil(bella)
        XCTAssertEqual(vm.activePetID, bella?.id)
        XCTAssertEqual(vm.name, "Bella")
        XCTAssertEqual(try store.currentPet()?.id, bella?.id)
        XCTAssertEqual(vm.pets.map(\.name).sorted(), ["Ana", "Bella"])
    }

    func testAddPetIsIdempotentlySeededViaActivityStore() throws {
        // Mirrors what Home does after addPet: switch has already activated the new pet, then
        // the caller seeds starter activity types through ActivityStore. Verifies the new pet
        // gets its own starter types (and re-seeding stays a no-op / doesn't duplicate).
        let store = PetStore(context: context, defaults: scratchDefaults)
        let activityStore = ActivityStore(context: context, petStore: store)
        try store.createPet(name: "Ana", species: "rabbit")
        try activityStore.seedDefaultsIfNeeded()
        let vm = PetProfileViewModel(store: store)

        let bella = try XCTUnwrap(vm.addPet(name: "Bella", species: "cat"))
        vm.reload()
        XCTAssertEqual(vm.activePetID, bella.id)

        try activityStore.seedDefaultsIfNeeded()
        let bellaTypes = try activityStore.types(includeArchived: true)
        XCTAssertEqual(bellaTypes.count, ActivityStore.defaultSeeds.count)
        XCTAssertTrue(bellaTypes.allSatisfy { $0.pet?.id == bella.id })

        // Re-seeding is idempotent: no duplicates for the active pet.
        try activityStore.seedDefaultsIfNeeded()
        XCTAssertEqual(try activityStore.types(includeArchived: true).count, ActivityStore.defaultSeeds.count)
    }
}
