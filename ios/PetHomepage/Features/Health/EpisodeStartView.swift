// ios/PetHomepage/Features/Health/EpisodeStartView.swift
import SwiftUI

struct EpisodeStartView: View {
    @State private var model: EpisodeStartViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: LogStore) {
        _model = State(initialValue: EpisodeStartViewModel(store: store))
    }

    var body: some View {
        BrandFormSheet(
            title: "New episode",
            systemImage: "waveform.path.ecg",
            confirmTitle: "Start",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { try? model.start(); dismiss() }
        ) {
            Section("Episode") {
                Picker("Category", selection: $model.category) {
                    ForEach(SymptomCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                TextField("Title (optional)", text: $model.title)
                DatePicker("Started", selection: $model.startedAt, displayedComponents: .date)
            }
        }
    }
}
