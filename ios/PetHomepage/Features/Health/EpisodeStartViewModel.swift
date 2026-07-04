// ios/PetHomepage/Features/Health/EpisodeStartViewModel.swift
import Foundation
import Observation

@Observable
final class EpisodeStartViewModel {
    var category: SymptomCategory = .digestive
    var title: String = ""
    var startedAt: Date = Date()

    private let store: LogStore

    init(store: LogStore) {
        self.store = store
    }

    /// Title is optional; a category is always selected, so the form is always valid.
    var isValid: Bool { true }

    func start() throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        try store.startEpisode(category: category,
                               title: trimmed.isEmpty ? nil : trimmed,
                               startedAt: startedAt)
    }
}
