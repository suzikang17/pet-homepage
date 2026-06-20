// ios/PetHomepage/Features/Vaccinations/VaccinationEditView.swift
import SwiftUI

struct VaccinationEditView: View {
    @State private var model: VaccinationEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: VaccinationStore, dueScheduler: DueReminderScheduler, editing: Vaccination?) {
        _model = State(initialValue: VaccinationEditViewModel(store: store, dueScheduler: dueScheduler, editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vaccine") {
                    TextField("Name", text: $model.vaccineName)
                    DatePicker("Administered", selection: $model.administeredAt, displayedComponents: .date)
                    TextField("Lot number", text: $model.lotNumber)
                    TextField("Administered by", text: $model.administeredBy)
                }
                Section("Next due") {
                    Toggle("Schedule next due", isOn: $model.hasNextDue)
                    if model.hasNextDue {
                        DatePicker("Due", selection: $model.nextDueAt, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Vaccination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            try? await model.save()
                            dismiss()
                        }
                    }
                    .disabled(!model.isValid)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .presentationDragIndicator(.visible)
        }
    }
}
