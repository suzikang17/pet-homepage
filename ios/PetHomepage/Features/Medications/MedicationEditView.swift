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
                }
                Section("Frequency") {
                    Picker("Repeat by", selection: $model.frequencyUnit) {
                        Text("Days").tag(FrequencyUnit.day)
                        Text("Weeks").tag(FrequencyUnit.week)
                        Text("Months").tag(FrequencyUnit.month)
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $model.frequencyInterval, in: 1...60) {
                        HStack {
                            Text("Every")
                            Spacer()
                            Text(model.frequencyLabel)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.primary)
                        }
                    }
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
            }
            .navigationTitle("Medication")
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
            .brandSheet()
        }
    }
}
