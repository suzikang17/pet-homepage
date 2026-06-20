// ios/PetHomepage/Features/Health/SymptomsListView.swift
import SwiftUI

struct SymptomsListView: View {
    @State private var model: SymptomsListViewModel
    @State private var showingStart = false

    private let episodeStore: SymptomEpisodeStore
    private let entryStore: SymptomEntryStore

    init(episodeStore: SymptomEpisodeStore, entryStore: SymptomEntryStore) {
        self.episodeStore = episodeStore
        self.entryStore = entryStore
        _model = State(initialValue: SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Active") {
                    if model.activeRows.isEmpty {
                        Text("No active episodes").foregroundStyle(.secondary)
                    }
                    ForEach(model.activeRows) { row in
                        episodeLink(row)
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { model.activeRows[$0] }
                        for row in targets { try? model.delete(row) }
                    }
                }
                Section("Resolved") {
                    if model.resolvedRows.isEmpty {
                        Text("No resolved episodes").foregroundStyle(.secondary)
                    }
                    ForEach(model.resolvedRows) { row in
                        episodeLink(row)
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { model.resolvedRows[$0] }
                        for row in targets { try? model.delete(row) }
                    }
                }
            }
            .navigationTitle("Symptoms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingStart = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingStart, onDismiss: { try? model.load() }) {
                EpisodeStartView(store: episodeStore)
            }
            .onAppear { try? model.load() }
        }
    }

    private func episodeLink(_ row: EpisodeRow) -> some View {
        NavigationLink {
            // EpisodeDetailView is wired in Task 6.
            Text(row.title)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.title).font(.headline)
                    Spacer()
                    if let severity = row.latestSeverity {
                        Text(severity.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(row.category.displayName) · started \(row.startedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
