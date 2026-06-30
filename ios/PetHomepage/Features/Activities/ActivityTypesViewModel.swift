// ios/PetHomepage/Features/Activities/ActivityTypesViewModel.swift
import Foundation
import Observation

@Observable
final class ActivityTypesViewModel {
    var types: [ActivityType] = []
    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
        reload()
    }

    func reload() { types = (try? store.types(includeArchived: false)) ?? [] }

    func archive(_ type: ActivityType) {
        try? store.archiveType(type)
        reload()
    }

    func update(_ type: ActivityType,
                name: String,
                category: ActivityCategory,
                iconName: String,
                defaultIntervalDays: Int) {
        try? store.updateType(type, name: name, category: category, iconName: iconName, defaultIntervalDays: defaultIntervalDays)
        reload()
    }
}
