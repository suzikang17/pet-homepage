// ios/PetHomepage/Features/Health/MarkerEditViewModel.swift
import Foundation
import Observation

@Observable
final class MarkerEditViewModel {
    var markerType: MarkerType = .weight
    var valueText: String = ""
    var unit: String = "lb"
    var recordedAt: Date = Date()

    private let store: HealthMarkerStore

    init(store: HealthMarkerStore) {
        self.store = store
    }

    /// Unit choices for the current marker type (empty = this type is unit-less).
    var unitOptions: [String] {
        switch markerType {
        case .weight: ["lb", "kg"]
        case .temperature: ["°C", "°F"]
        case .appetite, .energy, .water, .other: []
        }
    }

    /// Reset the unit to the first valid choice for the current type (or none).
    func syncUnitToType() {
        unit = unitOptions.first ?? ""
    }

    /// Valid when the value text parses to a finite Double.
    var isValid: Bool {
        guard let parsed = Double(valueText.trimmingCharacters(in: .whitespaces)) else { return false }
        return parsed.isFinite
    }

    func save() throws {
        guard let parsed = Double(valueText.trimmingCharacters(in: .whitespaces)), parsed.isFinite else { return }
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        try store.create(markerType: markerType,
                         value: parsed,
                         unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                         recordedAt: recordedAt)
    }
}
