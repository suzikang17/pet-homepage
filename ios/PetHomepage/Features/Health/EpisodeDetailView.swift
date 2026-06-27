// ios/PetHomepage/Features/Health/EpisodeDetailView.swift
import SwiftUI

struct EpisodeDetailView: View {
    @State private var model: EpisodeDetailViewModel

    init(episode: SymptomEpisode,
         episodeStore: SymptomEpisodeStore,
         entryStore: SymptomEntryStore) {
        _model = State(initialValue: EpisodeDetailViewModel(
            episode: episode,
            episodeStore: episodeStore,
            entryStore: entryStore
        ))
    }

    var body: some View {
        Form {
            Section("Episode") {
                LabeledContent("Category", value: model.episode.category.displayName)
                LabeledContent("Started", value: model.episode.startedAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Status", value: model.isResolved ? "Resolved" : "Active")
                if let resolvedAt = model.episode.resolvedAt {
                    LabeledContent("Resolved", value: resolvedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if !model.isResolved {
                    Button("Resolve episode") { try? model.resolve() }
                }
            }
            Section("Daily entries") {
                if model.entries.isEmpty {
                    Text("No entries yet").foregroundStyle(.secondary)
                }
                ForEach(model.entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.severity.displayName).font(.headline)
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let note = entry.note { Text(note).font(.subheadline) }
                        if let cause = entry.suspectedCause {
                            Text("Suspected: \(cause)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Add entry") {
                DatePicker("Date", selection: $model.newDate, displayedComponents: .date)
                Picker("Severity", selection: $model.newSeverity) {
                    ForEach(Severity.allCases) { severity in
                        Text(severity.displayName).tag(severity)
                    }
                }
                TextField("Note (optional)", text: $model.newNote)
                TextField("Suspected cause (optional)", text: $model.newSuspectedCause)
                Button("Add entry") { try? model.addEntry() }
            }
        }
        .navigationTitle(model.episode.title ?? model.episode.category.displayName)
        .brandSheet()
    }
}
