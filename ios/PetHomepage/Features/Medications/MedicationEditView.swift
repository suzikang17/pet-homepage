// ios/PetHomepage/Features/Medications/MedicationEditView.swift
import SwiftUI

struct MedicationEditView: View {
    @State private var model: MedicationEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: MedicationStore,
         reminderScheduler: MedicationReminderScheduler,
         veterinarianStore: VeterinarianStore,
         editing: Medication?) {
        _model = State(initialValue: MedicationEditViewModel(
            store: store,
            reminderScheduler: reminderScheduler,
            veterinarianStore: veterinarianStore,
            editing: editing
        ))
    }

    var body: some View {
        BrandFormSheet(
            title: "Medication",
            systemImage: "pills.fill",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); dismiss() } }
        ) {
            Section("Details") {
                TextField("Drug name", text: $model.drugName)
                TextField("Dosage", text: $model.dosage)
            }
            VetPickerSection(vets: model.availableVets, selected: $model.selectedVet)
            Section("Frequency") {
                Picker("Repeat by", selection: $model.frequencyUnit) {
                    Text("Days").tag(FrequencyUnit.day)
                    Text("Weeks").tag(FrequencyUnit.week)
                    Text("Months").tag(FrequencyUnit.month)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .onChange(of: model.frequencyUnit) { _, _ in model.resetNextReminderFromFrequency() }
                Stepper(value: $model.frequencyInterval, in: 1...60) {
                    HStack {
                        Text("Every")
                        Spacer()
                        Text(model.frequencyLabel)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.primary)
                    }
                }
                .listRowSeparator(.hidden)
                .onChange(of: model.frequencyInterval) { _, _ in model.resetNextReminderFromFrequency() }
            }
            Section {
                DatePicker("Reminder time", selection: $model.scheduleTime, displayedComponents: .hourAndMinute)
                DatePicker("Next reminder", selection: $model.nextReminder, displayedComponents: .date)
            } header: {
                Text("Reminder")
            } footer: {
                Text("You’ll be reminded then, repeating \(model.frequencyLabel.lowercased()).")
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
    }
}
