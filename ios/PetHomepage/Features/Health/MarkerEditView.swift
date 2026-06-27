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
                    .onChange(of: model.markerType) { _, _ in model.syncUnitToType() }
                    TextField("Value", text: $model.valueText)
                        .keyboardType(.decimalPad)
                    if !model.unitOptions.isEmpty {
                        Picker("Unit", selection: $model.unit) {
                            ForEach(model.unitOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    DatePicker("Recorded", selection: $model.recordedAt)
                }
            }
            .navigationTitle("Add marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? model.save()
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
            .brandSheet()
        }
    }
}
