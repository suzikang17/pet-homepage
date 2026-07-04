// ios/PetHomepageTests/EpisodeStartViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class EpisodeStartViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
    }

    func testIsValidIsAlwaysTrue() {
        let vm = EpisodeStartViewModel(store: logStore)
        XCTAssertTrue(vm.isValid)
    }

    func testStartCreatesActiveSymptomEpisodeWithTrimmedTitle() throws {
        let vm = EpisodeStartViewModel(store: logStore)
        vm.category = .digestive
        vm.title = "  Loose stool  "
        vm.startedAt = Date(timeIntervalSince1970: 1_000)

        try vm.start()

        let episodes = try logStore.episodes()
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.category, .digestive)
        XCTAssertEqual(episodes.first?.title, "Loose stool")
        XCTAssertEqual(episodes.first?.status, .active)
        XCTAssertEqual(episodes.first?.performedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testStartWithBlankTitleStoresNilTitle() throws {
        let vm = EpisodeStartViewModel(store: logStore)
        vm.title = "   "

        try vm.start()

        XCTAssertNil(try logStore.episodes().first?.title)
    }
}
