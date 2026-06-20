// ios/PetHomepageTests/SymptomsListViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class SymptomsListViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var episodeStore: SymptomEpisodeStore!
    private var entryStore: SymptomEntryStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        episodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
        entryStore = SymptomEntryStore(context: context)
    }

    func testLoadPartitionsActiveAndResolvedRows() throws {
        let active = try episodeStore.start(category: .digestive, title: "Loose stool", startedAt: Date(timeIntervalSince1970: 1_000))
        let resolved = try episodeStore.start(category: .skin, title: "Itch", startedAt: Date(timeIntervalSince1970: 2_000))
        try episodeStore.resolve(resolved, at: Date(timeIntervalSince1970: 6_000))
        _ = active

        let vm = SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore)
        try vm.load()

        XCTAssertEqual(vm.activeRows.map(\.title), ["Loose stool"])
        XCTAssertEqual(vm.resolvedRows.map(\.title), ["Itch"])
    }

    func testRowCarriesLatestSeverity() throws {
        let episode = try episodeStore.start(category: .digestive, title: "Loose stool", startedAt: Date(timeIntervalSince1970: 1_000))
        try entryStore.addEntry(to: episode, date: Date(timeIntervalSince1970: 2_000), severity: .mild, note: nil, suspectedCause: nil)
        try entryStore.addEntry(to: episode, date: Date(timeIntervalSince1970: 5_000), severity: .severe, note: nil, suspectedCause: nil)

        let vm = SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore)
        try vm.load()

        XCTAssertEqual(vm.activeRows.first?.latestSeverity, .severe)
    }

    func testRowFallsBackToTitleFromCategoryWhenTitleNil() throws {
        _ = try episodeStore.start(category: .behavior, title: nil, startedAt: Date(timeIntervalSince1970: 1_000))

        let vm = SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore)
        try vm.load()

        XCTAssertEqual(vm.activeRows.first?.title, "Behavior")
    }

    func testDeleteRemovesEpisodeOnReload() throws {
        _ = try episodeStore.start(category: .diet, title: "Off food", startedAt: Date(timeIntervalSince1970: 1_000))
        let vm = SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore)
        try vm.load()
        let row = try XCTUnwrap(vm.activeRows.first)

        try vm.delete(row)

        XCTAssertTrue(vm.activeRows.isEmpty)
    }
}
