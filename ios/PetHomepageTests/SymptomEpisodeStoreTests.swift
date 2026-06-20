// ios/PetHomepageTests/SymptomEpisodeStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class SymptomEpisodeStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
    }

    func testStartCreatesActiveEpisodeScopedToCurrentPet() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        let episode = try store.start(category: .digestive,
                                      title: "Loose stool",
                                      startedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(episode.category, .digestive)
        XCTAssertEqual(episode.title, "Loose stool")
        XCTAssertEqual(episode.status, .active)
        XCTAssertNil(episode.resolvedAt)
        XCTAssertEqual(episode.pet?.name, "Sandy")
        XCTAssertNotNil(episode.id)
    }

    func testActiveAndResolvedPartitionEpisodes() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        let a = try store.start(category: .digestive, title: "A", startedAt: Date(timeIntervalSince1970: 1_000))
        _ = try store.start(category: .skin, title: "B", startedAt: Date(timeIntervalSince1970: 2_000))
        try store.resolve(a, at: Date(timeIntervalSince1970: 5_000))

        XCTAssertEqual(try store.activeEpisodes().map(\.title), ["B"])
        XCTAssertEqual(try store.resolvedEpisodes().map(\.title), ["A"])
    }

    func testEpisodesAreSortedMostRecentlyStartedFirst() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        _ = try store.start(category: .diet, title: "Old", startedAt: Date(timeIntervalSince1970: 1_000))
        _ = try store.start(category: .energy, title: "New", startedAt: Date(timeIntervalSince1970: 9_000))

        XCTAssertEqual(try store.episodes().map(\.title), ["New", "Old"])
    }

    func testResolveSetsStatusAndResolvedAt() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        let episode = try store.start(category: .behavior, title: nil, startedAt: Date(timeIntervalSince1970: 0))
        let when = Date(timeIntervalSince1970: 8_000)

        try store.resolve(episode, at: when)

        XCTAssertEqual(episode.status, .resolved)
        XCTAssertEqual(episode.resolvedAt, when)
    }

    func testUpdateChangesCategoryAndTitle() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        let episode = try store.start(category: .other, title: "TBD", startedAt: Date())

        try store.update(episode, category: .skin, title: "Itchy ears")

        XCTAssertEqual(episode.category, .skin)
        XCTAssertEqual(episode.title, "Itchy ears")
    }

    func testDeleteRemovesEpisode() throws {
        let store = SymptomEpisodeStore(context: context, petStore: petStore)
        let episode = try store.start(category: .digestive, title: "X", startedAt: Date())
        try store.delete(episode)
        XCTAssertEqual(try store.episodes().count, 0)
    }

    func testEpisodesIsEmptyWhenNoPetExists() throws {
        let emptyContext = PersistenceController(inMemory: true).container.viewContext
        let store = SymptomEpisodeStore(context: emptyContext, petStore: PetStore(context: emptyContext))
        XCTAssertEqual(try store.episodes().count, 0)
        XCTAssertEqual(try store.activeEpisodes().count, 0)
        XCTAssertEqual(try store.resolvedEpisodes().count, 0)
    }
}
