// ios/PetHomepageTests/LogStoreSymptomTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class LogStoreSymptomTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = LogStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testStartEpisodeStampsKindAndFieldsAsActive() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let episode = try store.startEpisode(category: .digestive, title: "Loose stool", startedAt: started)

        XCTAssertEqual(episode.kind, .symptom)
        XCTAssertEqual(episode.category, .digestive)
        XCTAssertEqual(episode.title, "Loose stool")
        XCTAssertEqual(episode.performedAt, started)
        XCTAssertEqual(episode.status, .active)
        XCTAssertNil(episode.resolvedAt)
        XCTAssertEqual(episode.pet?.name, "Sandy")
        XCTAssertNotNil(episode.id)
    }

    func testEpisodesQueryOnlyReturnsSymptomKindNewestFirst() throws {
        _ = try store.createDiary(performedAt: Date(timeIntervalSince1970: 50), note: "not an episode")
        let older = try store.startEpisode(category: .diet, title: "Old", startedAt: Date(timeIntervalSince1970: 100))
        let newer = try store.startEpisode(category: .energy, title: "New", startedAt: Date(timeIntervalSince1970: 300))

        let episodes = try store.episodes()

        XCTAssertEqual(episodes.map(\.id), [newer.id, older.id])
        XCTAssertEqual(try store.diaryEntries().count, 1)
    }

    func testResolveEpisodeSetsStatusAndResolvedAt() throws {
        let episode = try store.startEpisode(category: .behavior, title: nil, startedAt: Date(timeIntervalSince1970: 0))
        let when = Date(timeIntervalSince1970: 8_000)

        try store.resolveEpisode(episode, at: when)

        XCTAssertEqual(episode.status, .resolved)
        XCTAssertEqual(episode.resolvedAt, when)
    }

    func testCategoryAndStatusRoundTripThroughSubtypeAndStatusRaw() throws {
        let episode = try store.startEpisode(category: .skin, title: "Itchy ears", startedAt: Date())

        XCTAssertEqual(episode.subtypeRaw, SymptomCategory.skin.rawValue)
        XCTAssertEqual(episode.statusRaw, EpisodeStatus.active.rawValue)

        episode.category = .other
        episode.status = .resolved
        XCTAssertEqual(episode.subtypeRaw, SymptomCategory.other.rawValue)
        XCTAssertEqual(episode.statusRaw, EpisodeStatus.resolved.rawValue)
    }

    func testEmptyWithoutPetReturnsNoEpisodes() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let s = LogStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try s.episodes().count, 0)
    }
}
