// ios/PetHomepageTests/HomeLocationStoreTests.swift
import XCTest

@testable import PetHomepage

final class HomeLocationStoreTests: XCTestCase {
    private var store: HomeLocationStore!

    override func setUp() {
        store = HomeLocationStore(defaults: UserDefaults(suiteName: "home-\(UUID().uuidString)")!)
    }

    func testUnconfiguredByDefault() {
        XCTAssertNil(store.homeCoordinate)
        XCTAssertNil(store.defaultActivityTypeID)
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(store.promptRule, .anyWalk)
    }

    func testCoordinateRoundTripAndClear() {
        store.homeCoordinate = (latitude: 37.77, longitude: -122.43)
        XCTAssertEqual(store.homeCoordinate?.latitude, 37.77)
        XCTAssertEqual(store.homeCoordinate?.longitude, -122.43)
        store.homeCoordinate = nil
        XCTAssertNil(store.homeCoordinate)
    }

    /// Home alone arms detection — the activity a detected walk logs as is resolved
    /// automatically (WalkActivityResolver), so an unmade choice can't silently disarm it.
    func testConfiguredNeedsHomeOnly() {
        XCTAssertFalse(store.isConfigured)
        store.homeCoordinate = (latitude: 37.77, longitude: -122.43)
        XCTAssertTrue(store.isConfigured)
        XCTAssertNil(store.defaultActivityTypeID)
    }

    func testPromptRulePersists() {
        store.promptRule = .scheduledOnly
        XCTAssertEqual(store.promptRule, .scheduledOnly)
        store.promptRule = .off
        XCTAssertEqual(store.promptRule, .off)
    }
}
