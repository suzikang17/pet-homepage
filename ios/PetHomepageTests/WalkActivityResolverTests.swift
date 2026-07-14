// ios/PetHomepageTests/WalkActivityResolverTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class WalkActivityResolverTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var home: HomeLocationStore!
    private var activityStore: ActivityStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        defaults = UserDefaults(suiteName: "walk-resolver-\(UUID().uuidString)")
        home = HomeLocationStore(defaults: defaults)
        let petStore = PetStore(context: context, defaults: defaults)
        _ = try petStore.ensurePet()
        activityStore = ActivityStore(context: context, petStore: petStore)
    }

    func testHomeOnlyIsEnoughToBeConfigured() {
        XCTAssertFalse(home.isConfigured)
        home.homeCoordinate = (latitude: 37.77, longitude: -122.43)
        // No activity type chosen — detection must still arm.
        XCTAssertNil(home.defaultActivityTypeID)
        XCTAssertTrue(home.isConfigured)
    }

    func testExplicitChoiceWins() throws {
        let chosen = try activityStore.createType(name: "Evening stroll", category: .training,
                                                  iconName: "figure.walk", defaultIntervalDays: 0)
        _ = try activityStore.createType(name: "Walk", category: .training,
                                         iconName: "figure.walk", defaultIntervalDays: 0)
        home.defaultActivityTypeID = chosen.id
        let resolved = WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
        XCTAssertEqual(resolved, chosen.id)
    }

    func testFallsBackToWalkNamedType() throws {
        _ = try activityStore.createType(name: "Bath", category: .care,
                                         iconName: "shower", defaultIntervalDays: 0)
        let walk = try activityStore.createType(name: "Morning walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let resolved = WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
        XCTAssertEqual(resolved, walk.id)
        XCTAssertEqual(home.defaultActivityTypeID, walk.id) // remembered
    }

    func testCreatesWalkTypeWhenNoneExists() throws {
        // Fresh store: no activity types at all (defaults are seeded by the app, not tests).
        XCTAssertTrue(try activityStore.types().isEmpty)
        let resolved = WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
        XCTAssertNotNil(resolved)
        let created = try XCTUnwrap(try activityStore.types().first { $0.id == resolved })
        XCTAssertTrue(created.name.localizedCaseInsensitiveContains("walk"))
    }

    func testStaleChoiceIsReResolved() throws {
        home.defaultActivityTypeID = UUID() // points at a deleted type
        let walk = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let resolved = WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
        XCTAssertEqual(resolved, walk.id)
    }
}
