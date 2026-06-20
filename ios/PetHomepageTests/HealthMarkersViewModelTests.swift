// ios/PetHomepageTests/HealthMarkersViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class HealthMarkersViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: HealthMarkerStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = HealthMarkerStore(context: context, petStore: petStore)
    }

    func testLoadBuildsOneLatestRowPerMarkerType() throws {
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.create(markerType: .weight, value: 12.6, unit: "kg", recordedAt: Date(timeIntervalSince1970: 5_000))
        try store.create(markerType: .energy, value: 4, unit: nil, recordedAt: Date(timeIntervalSince1970: 2_000))

        let vm = HealthMarkersViewModel(store: store)
        try vm.load()

        XCTAssertEqual(vm.latestRows.count, 2)
        let weightRow = try XCTUnwrap(vm.latestRows.first { $0.markerType == .weight })
        XCTAssertEqual(weightRow.value, 12.6)
        XCTAssertEqual(vm.latestRows.first?.markerType, .weight) // weight ordered first
    }

    func testLoadBuildsTimeOrderedWeightSeriesAndLatestWeight() throws {
        try store.create(markerType: .weight, value: 12.6, unit: "kg", recordedAt: Date(timeIntervalSince1970: 5_000))
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        try store.create(markerType: .weight, value: 12.3, unit: "kg", recordedAt: Date(timeIntervalSince1970: 3_000))

        let vm = HealthMarkersViewModel(store: store)
        try vm.load()

        XCTAssertEqual(vm.weightSeries.map(\.value), [12.0, 12.3, 12.6])
        XCTAssertEqual(vm.latestWeight, 12.6)
    }

    func testWeightSeriesEmptyAndLatestNilWhenNoWeight() throws {
        try store.create(markerType: .water, value: 500, unit: "ml", recordedAt: Date())
        let vm = HealthMarkersViewModel(store: store)
        try vm.load()

        XCTAssertTrue(vm.weightSeries.isEmpty)
        XCTAssertNil(vm.latestWeight)
    }

    func testDeleteRemovesRowOnReload() throws {
        try store.create(markerType: .weight, value: 12.0, unit: "kg", recordedAt: Date(timeIntervalSince1970: 1_000))
        let vm = HealthMarkersViewModel(store: store)
        try vm.load()
        XCTAssertEqual(vm.latestRows.count, 1)

        let marker = try XCTUnwrap(store.markers().first)
        try vm.delete(marker)

        XCTAssertEqual(vm.latestRows.count, 0)
        XCTAssertNil(vm.latestWeight)
    }
}
