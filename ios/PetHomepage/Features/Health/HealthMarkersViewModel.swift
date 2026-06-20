// ios/PetHomepage/Features/Health/HealthMarkersViewModel.swift
import Foundation
import Observation

/// The latest recorded value for one marker type — one row per type in the list.
struct MarkerLatestRow: Identifiable {
    let id: String          // markerType.rawValue (one row per type)
    let markerType: MarkerType
    let value: Double
    let unit: String?
    let recordedAt: Date
}

/// One point on the weight trend.
struct WeightPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

@Observable
final class HealthMarkersViewModel {
    var latestRows: [MarkerLatestRow] = []
    var weightSeries: [WeightPoint] = []
    var latestWeight: Double?

    private let store: HealthMarkerStore

    init(store: HealthMarkerStore) {
        self.store = store
    }

    func load() throws {
        // One latest row per marker type, ordered by MarkerType.allCases (weight first).
        latestRows = try MarkerType.allCases.compactMap { type in
            guard let marker = try store.latest(of: type) else { return nil }
            return MarkerLatestRow(id: type.rawValue,
                                   markerType: type,
                                   value: marker.value,
                                   unit: marker.unit,
                                   recordedAt: marker.recordedAt)
        }

        // Weight trend: oldest-first series.
        let weights = try store.series(of: .weight)
        weightSeries = weights.map { WeightPoint(id: $0.id, date: $0.recordedAt, value: $0.value) }
        latestWeight = try store.latest(of: .weight)?.value
    }

    func delete(_ marker: HealthMarker) throws {
        try store.delete(marker)
        try load()
    }
}
