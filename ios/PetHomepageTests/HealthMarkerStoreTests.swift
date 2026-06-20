// ios/PetHomepageTests/HealthMarkerStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class HealthMarkerStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
    }

    func testCreateMarkerIsScopedToCurrentPet() throws {
        let store = HealthMarkerStore(context: context, petStore: petStore)
        try store.create(markerType: .weight, value: 12.4, unit: "kg", recordedAt: Date(timeIntervalSince1970: 0))

        let markers = try store.markers()
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.markerType, .weight)
        XCTAssertEqual(markers.first?.value, 12.4)
        XCTAssertEqual(markers.first?.unit, "kg")
        XCTAssertEqual(markers.first?.pet?.name, "Sandy")
        XCTAssertNotNil(markers.first?.id)
    }

    func testLatestReturnsMostRecentMarkerOfType() throws {
        let store = HealthMarkerStore(context: context, petStore: petStore)
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.create(markerType: .weight, value: 12.5, unit: "kg", recordedAt: Date(timeIntervalSince1970: 3_000))
        try store.create(markerType: .weight, value: 12.2, unit: "kg", recordedAt: Date(timeIntervalSince1970: 2_000))
        try store.create(markerType: .energy, value: 4, unit: nil, recordedAt: Date(timeIntervalSince1970: 9_000))

        XCTAssertEqual(try store.latest(of: .weight)?.value, 12.5)
        XCTAssertEqual(try store.latest(of: .energy)?.value, 4)
    }

    func testLatestIsNilWhenNoneOfThatType() throws {
        let store = HealthMarkerStore(context: context, petStore: petStore)
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date())
        XCTAssertNil(try store.latest(of: .water))
    }

    func testSeriesIsTimeOrderedAndFilteredByType() throws {
        let store = HealthMarkerStore(context: context, petStore: petStore)
        try store.create(markerType: .weight, value: 12.5, unit: "kg", recordedAt: Date(timeIntervalSince1970: 3_000))
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.create(markerType: .weight, value: 12.2, unit: "kg", recordedAt: Date(timeIntervalSince1970: 2_000))
        try store.create(markerType: .water, value: 500, unit: "ml", recordedAt: Date(timeIntervalSince1970: 1_500))

        let weights = try store.series(of: .weight)
        XCTAssertEqual(weights.map(\.value), [12.0, 12.2, 12.5])
        XCTAssertEqual(try store.series(of: .water).map(\.value), [500])
    }

    func testDeleteRemovesMarker() throws {
        let store = HealthMarkerStore(context: context, petStore: petStore)
        let marker = try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date())
        try store.delete(marker)
        XCTAssertEqual(try store.markers().count, 0)
    }

    func testMarkersIsEmptyWhenNoPetExists() throws {
        let emptyContext = PersistenceController(inMemory: true).container.viewContext
        let store = HealthMarkerStore(context: emptyContext, petStore: PetStore(context: emptyContext))
        XCTAssertEqual(try store.markers().count, 0)
        XCTAssertNil(try store.latest(of: .weight))
        XCTAssertEqual(try store.series(of: .weight).count, 0)
    }
}
