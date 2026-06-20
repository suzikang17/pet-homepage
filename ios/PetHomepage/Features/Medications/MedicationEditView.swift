// ios/PetHomepage/Features/Medications/MedicationEditView.swift
import SwiftUI

struct MedicationEditView: View {
    @State private var model: MedicationEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: MedicationStore, reminderScheduler: MedicationReminderScheduler, editing: Medication?) {
        _model = State(initialValue: MedicationEditViewModel(
            store: store,
            reminderScheduler: reminderScheduler,
            editing: editing
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Drug name", text: $model.drugName)
                    TextField("Dosage", text: $model.dosage)
                    TextField("Frequency", text: $model.frequency)
                }
                Section("Reminder") {
                    DatePicker("Time", selection: $model.scheduleTime, displayedComponents: .hourAndMinute)
                    DatePicker("Started", selection: $model.startedAt, displayedComponents: .date)
                }
                Section("Refill") {
                    Toggle("Track refill", isOn: $model.hasRefillDue)
                    if model.hasRefillDue {
                        DatePicker("Refill due", selection: $model.refillDueAt, displayedComponents: .date)
                    }
                }
                Section("End") {
                    Toggle("Ended", isOn: $model.hasEnded)
                    if model.hasEnded {
                        DatePicker("Ended", selection: $model.endedAt, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Save") {
                        Task {
                            try? await model.save()
                            dismiss()
                        }
                    }
                    .disabled(!model.isValid)
                }
            }
            .navigationTitle("Medication")
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .presentationDragIndicator(.visible)
        }
    }
}
