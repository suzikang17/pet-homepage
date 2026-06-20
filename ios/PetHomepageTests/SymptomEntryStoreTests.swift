// ios/PetHomepageTests/SymptomEntryStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class SymptomEntryStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var episodeStore: SymptomEpisodeStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        episodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
    }

    private func makeEpisode() throws -> SymptomEpisode {
        try episodeStore.start(category: .digestive, title: "Loose stool", startedAt: Date(timeIntervalSince1970: 0))
    }

    func testAddEntryLinksToEpisode() throws {
        let store = SymptomEntryStore(context: context)
        let episode = try makeEpisode()

        let entry = try store.addEntry(to: episode,
                                       date: Date(timeIntervalSince1970: 1_000),
                                       severity: .moderate,
                                       note: "Skipped breakfast",
                                       suspectedCause: "New treats")

        XCTAssertEqual(entry.episode?.id, episode.id)
        XCTAssertEqual(entry.severity, .moderate)
        XCTAssertEqual(entry.note, "Skipped breakfast")
        XCTAssertEqual(entry.suspectedCause, "New treats")
        XCTAssertNotNil(entry.id)
    }

    func testEntriesForEpisodeAreSortedByDateAscending() throws {
        let store = SymptomEntryStore(context: context)
        let episode = try makeEpisode()
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 3_000), severity: .severe, note: nil, suspectedCause: nil)
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 1_000), severity: .mild, note: nil, suspectedCause: nil)
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 2_000), severity: .moderate, note: nil, suspectedCause: nil)

        let severities = try store.entries(for: episode).map(\.severity)
        XCTAssertEqual(severities, [.mild, .moderate, .severe])
    }

    func testEntriesAreScopedToTheirEpisode() throws {
        let store = SymptomEntryStore(context: context)
        let a = try makeEpisode()
        let b = try episodeStore.start(category: .skin, title: "Itch", startedAt: Date(timeIntervalSince1970: 5_000))
        try store.addEntry(to: a, date: Date(timeIntervalSince1970: 1_000), severity: .mild, note: nil, suspectedCause: nil)
        try store.addEntry(to: a, date: Date(timeIntervalSince1970: 2_000), severity: .mild, note: nil, suspectedCause: nil)
        try store.addEntry(to: b, date: Date(timeIntervalSince1970: 6_000), severity: .severe, note: nil, suspectedCause: nil)

        XCTAssertEqual(try store.entries(for: a).count, 2)
        XCTAssertEqual(try store.entries(for: b).count, 1)
    }

    func testLatestEntryReturnsMostRecentByDate() throws {
        let store = SymptomEntryStore(context: context)
        let episode = try makeEpisode()
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 1_000), severity: .mild, note: "first", suspectedCause: nil)
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 9_000), severity: .severe, note: "latest", suspectedCause: nil)
        try store.addEntry(to: episode, date: Date(timeIntervalSince1970: 5_000), severity: .moderate, note: "middle", suspectedCause: nil)

        XCTAssertEqual(try store.latestEntry(for: episode)?.note, "latest")
    }

    func testLatestEntryIsNilWhenNoEntries() throws {
        let store = SymptomEntryStore(context: context)
        let episode = try makeEpisode()
        XCTAssertNil(try store.latestEntry(for: episode))
    }

    func testDeleteRemovesEntry() throws {
        let store = SymptomEntryStore(context: context)
        let episode = try makeEpisode()
        let entry = try store.addEntry(to: episode, date: Date(), severity: .mild, note: nil, suspectedCause: nil)
        try store.delete(entry)
        XCTAssertEqual(try store.entries(for: episode).count, 0)
    }
}
