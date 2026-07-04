// ios/PetHomepageTests/LogStoreMarkerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class LogStoreMarkerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = LogStore(context: context, petStore: petStore)
    }

    func testLogMarkerStampsKindAndFields() throws {
        let recorded = Date(timeIntervalSince1970: 1_700_000_000)
        let marker = try store.logMarker(type: .weight, value: 12.4, unit: "kg", recordedAt: recorded)

        XCTAssertEqual(marker.kind, .marker)
        XCTAssertEqual(marker.markerType, .weight)
        XCTAssertEqual(marker.value, 12.4)
        XCTAssertEqual(marker.unit, "kg")
        XCTAssertEqual(marker.performedAt, recorded)
        XCTAssertEqual(marker.pet?.name, "Sandy")
        XCTAssertNotNil(marker.id)
    }

    func testMarkersQueryOnlyReturnsMarkerKindNewestFirst() throws {
        _ = try store.createDiary(performedAt: Date(timeIntervalSince1970: 50), note: "not a marker")
        let older = try store.logMarker(type: .weight, value: 12.0, unit: "kg",
                                        recordedAt: Date(timeIntervalSince1970: 100))
        let newer = try store.logMarker(type: .weight, value: 12.5, unit: "kg",
                                        recordedAt: Date(timeIntervalSince1970: 300))

        let markers = try store.markers()

        XCTAssertEqual(markers.map(\.id), [newer.id, older.id])
        XCTAssertEqual(try store.diaryEntries().count, 1)
    }

    func testLatestMarkerReturnsMostRecentOfType() throws {
        try store.logMarker(type: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.logMarker(type: .weight, value: 12.5, unit: "kg", recordedAt: Date(timeIntervalSince1970: 3_000))
        try store.logMarker(type: .weight, value: 12.2, unit: "kg", recordedAt: Date(timeIntervalSince1970: 2_000))
        try store.logMarker(type: .energy, value: 4, unit: nil, recordedAt: Date(timeIntervalSince1970: 9_000))

        XCTAssertEqual(try store.latestMarker(of: .weight)?.value, 12.5)
        XCTAssertEqual(try store.latestMarker(of: .energy)?.value, 4)
    }

    func testLatestMarkerIsNilWhenNoneOfThatType() throws {
        try store.logMarker(type: .weight, value: 12.0, unit: "kg", recordedAt: Date())
        XCTAssertNil(try store.latestMarker(of: .water))
    }

    func testSeriesIsTimeOrderedAndFilteredByType() throws {
        try store.logMarker(type: .weight, value: 12.5, unit: "kg", recordedAt: Date(timeIntervalSince1970: 3_000))
        try store.logMarker(type: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.logMarker(type: .weight, value: 12.2, unit: "kg", recordedAt: Date(timeIntervalSince1970: 2_000))
        try store.logMarker(type: .water, value: 500, unit: "ml", recordedAt: Date(timeIntervalSince1970: 1_500))

        let weights = try store.series(of: .weight)
        XCTAssertEqual(weights.map(\.value), [12.0, 12.2, 12.5])
        XCTAssertEqual(try store.series(of: .water).map(\.value), [500])
    }

    func testEmptyWithoutPetReturnsNoMarkers() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let s = LogStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try s.markers().count, 0)
        XCTAssertNil(try s.latestMarker(of: .weight))
        XCTAssertEqual(try s.series(of: .weight).count, 0)
    }
}
