// ios/PetHomepageTests/EpisodeDetailViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class EpisodeDetailViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!
    private var entryStore: SymptomEntryStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        entryStore = SymptomEntryStore(context: context)
    }

    private func makeVM() throws -> EpisodeDetailViewModel {
        let episode = try logStore.startEpisode(category: .digestive, title: "Loose stool", startedAt: Date(timeIntervalSince1970: 0))
        return EpisodeDetailViewModel(episode: episode, logStore: logStore, entryStore: entryStore)
    }

    func testLoadShowsEntriesOldestFirst() throws {
        let vm = try makeVM()
        try entryStore.addEntry(to: vm.episode, date: Date(timeIntervalSince1970: 3_000), severity: .severe, note: "c", suspectedCause: nil)
        try entryStore.addEntry(to: vm.episode, date: Date(timeIntervalSince1970: 1_000), severity: .mild, note: "a", suspectedCause: nil)

        try vm.load()

        XCTAssertEqual(vm.entries.map(\.note), ["a", "c"])
    }

    func testAddEntryAppendsAndClearsForm() throws {
        let vm = try makeVM()
        vm.newSeverity = .moderate
        vm.newNote = "Skipped dinner"
        vm.newSuspectedCause = "New treats"
        vm.newDate = Date(timeIntervalSince1970: 2_000)

        try vm.addEntry()

        XCTAssertEqual(vm.entries.count, 1)
        XCTAssertEqual(vm.entries.first?.severity, .moderate)
        XCTAssertEqual(vm.entries.first?.note, "Skipped dinner")
        XCTAssertEqual(vm.entries.first?.suspectedCause, "New treats")
        XCTAssertEqual(vm.newNote, "")
        XCTAssertEqual(vm.newSuspectedCause, "")
        XCTAssertEqual(vm.newSeverity, .mild) // reset to default
    }

    func testResolveMarksEpisodeResolved() throws {
        let vm = try makeVM()
        XCTAssertFalse(vm.isResolved)

        try vm.resolve()

        XCTAssertTrue(vm.isResolved)
        XCTAssertEqual(vm.episode.status, .resolved)
        XCTAssertNotNil(vm.episode.resolvedAt)
    }
}
