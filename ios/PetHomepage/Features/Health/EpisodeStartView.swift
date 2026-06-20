// ios/PetHomepage/Features/Health/EpisodeStartView.swift
import SwiftUI

struct EpisodeStartView: View {
    @State private var model: EpisodeStartViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: SymptomEpisodeStore) {
        _model = State(initialValue: EpisodeStartViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Episode") {
                    Picker("Category", selection: $model.category) {
                        ForEach(SymptomCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    TextField("Title (optional)", text: $model.title)
                    DatePicker("Started", selection: $model.startedAt, displayedComponents: .date)
                }
                Section {
                    Button("Start tracking") {
                        try? model.start()
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
            .navigationTitle("New episode")
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .presentationDragIndicator(.visible)
        }
    }
}
