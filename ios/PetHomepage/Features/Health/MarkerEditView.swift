// ios/PetHomepage/Features/Health/MarkerEditView.swift
import SwiftUI

struct MarkerEditView: View {
    @State private var model: MarkerEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: HealthMarkerStore) {
        _model = State(initialValue: MarkerEditViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Marker") {
                    Picker("Type", selection: $model.markerType) {
                        ForEach(MarkerType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Value", text: $model.valueText)
                        .keyboardType(.decimalPad)
                    TextField("Unit (optional)", text: $model.unit)
                    DatePicker("Recorded", selection: $model.recordedAt)
                }
                Section {
                    Button("Save") {
                        try? model.save()
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
            .navigationTitle("Add marker")
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .presentationDragIndicator(.visible)
        }
    }
}
