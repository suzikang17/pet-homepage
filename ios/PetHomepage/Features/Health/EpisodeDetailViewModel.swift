// ios/PetHomepage/Features/Health/EpisodeDetailViewModel.swift
import Foundation
import Observation

@Observable
final class EpisodeDetailViewModel {
    let episode: LogEntry
    var entries: [SymptomEntry] = []

    // Add-entry form fields.
    var newSeverity: Severity = .mild
    var newNote: String = ""
    var newSuspectedCause: String = ""
    var newDate: Date = Date()

    private let logStore: LogStore
    private let entryStore: SymptomEntryStore

    init(episode: LogEntry,
         logStore: LogStore,
         entryStore: SymptomEntryStore) {
        self.episode = episode
        self.logStore = logStore
        self.entryStore = entryStore
        try? load()
    }

    var isResolved: Bool {
        episode.status == .resolved
    }

    func load() throws {
        entries = try entryStore.entries(for: episode)
    }

    func addEntry() throws {
        let note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let cause = newSuspectedCause.trimmingCharacters(in: .whitespacesAndNewlines)
        try entryStore.addEntry(to: episode,
                                date: newDate,
                                severity: newSeverity,
                                note: note.isEmpty ? nil : note,
                                suspectedCause: cause.isEmpty ? nil : cause)
        // Reset the form to defaults.
        newSeverity = .mild
        newNote = ""
        newSuspectedCause = ""
        newDate = Date()
        try load()
    }

    func resolve() throws {
        try logStore.resolveEpisode(episode, at: Date())
    }
}
