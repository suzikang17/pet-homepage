// ios/PetHomepage/Features/Health/SymptomsListView.swift
import SwiftUI

/// Content-only — embedded in HealthTabView, which provides the NavigationStack,
/// the gradient hero, and the "+" (bound to `showingStart`).
struct SymptomsListView: View {
    @State private var model: SymptomsListViewModel
    @Binding var showingStart: Bool

    private let episodeStore: SymptomEpisodeStore
    private let entryStore: SymptomEntryStore

    init(episodeStore: SymptomEpisodeStore, entryStore: SymptomEntryStore, showingStart: Binding<Bool>) {
        self.episodeStore = episodeStore
        self.entryStore = entryStore
        _showingStart = showingStart
        _model = State(initialValue: SymptomsListViewModel(episodeStore: episodeStore, entryStore: entryStore))
    }

    var body: some View {
        List {
            Section("Active") {
                if model.activeRows.isEmpty {
                    Text("No active episodes").foregroundStyle(Theme.inkSoft)
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
                    Text("No resolved episodes").foregroundStyle(Theme.inkSoft)
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
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .sheet(isPresented: $showingStart, onDismiss: { try? model.load() }) {
            EpisodeStartView(store: episodeStore)
        }
        .onAppear { try? model.load() }
    }

    private func episodeLink(_ row: EpisodeRow) -> some View {
        NavigationLink {
            EpisodeDetailView(episode: row.episode, episodeStore: episodeStore, entryStore: entryStore)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.title).font(Theme.headline()).foregroundStyle(Theme.ink)
                    Spacer()
                    if let severity = row.latestSeverity {
                        Text(severity.displayName).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text("\(row.category.displayName) · started \(row.startedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}
