// ios/PetHomepage/Features/Health/SymptomsListViewModel.swift
import Foundation
import Observation

struct EpisodeRow: Identifiable {
    let id: UUID
    let episode: SymptomEpisode
    let title: String
    let category: SymptomCategory
    let startedAt: Date
    let latestSeverity: Severity?
}

@Observable
final class SymptomsListViewModel {
    var activeRows: [EpisodeRow] = []
    var resolvedRows: [EpisodeRow] = []

    private let episodeStore: SymptomEpisodeStore
    private let entryStore: SymptomEntryStore

    init(episodeStore: SymptomEpisodeStore, entryStore: SymptomEntryStore) {
        self.episodeStore = episodeStore
        self.entryStore = entryStore
    }

    func load() throws {
        activeRows = try episodeStore.activeEpisodes().map { try row(for: $0) }
        resolvedRows = try episodeStore.resolvedEpisodes().map { try row(for: $0) }
    }

    func delete(_ row: EpisodeRow) throws {
        try episodeStore.delete(row.episode)
        try load()
    }

    private func row(for episode: SymptomEpisode) throws -> EpisodeRow {
        let title = episode.title?.trimmingCharacters(in: .whitespaces)
        let displayTitle = (title?.isEmpty == false) ? title! : episode.category.displayName
        return EpisodeRow(
            id: episode.id,
            episode: episode,
            title: displayTitle,
            category: episode.category,
            startedAt: episode.startedAt,
            latestSeverity: try entryStore.latestEntry(for: episode)?.severity
        )
    }
}
