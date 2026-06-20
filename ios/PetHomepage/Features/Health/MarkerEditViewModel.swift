// ios/PetHomepage/Features/Health/MarkerEditViewModel.swift
import Foundation
import Observation

@Observable
final class MarkerEditViewModel {
    var markerType: MarkerType = .weight
    var valueText: String = ""
    var unit: String = "kg"
    var recordedAt: Date = Date()

    private let store: HealthMarkerStore

    init(store: HealthMarkerStore) {
        self.store = store
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
