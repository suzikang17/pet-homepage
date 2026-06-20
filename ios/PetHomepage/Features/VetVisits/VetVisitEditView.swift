// ios/PetHomepage/Features/VetVisits/VetVisitEditView.swift
import SwiftUI

struct VetVisitEditView: View {
    @State private var model: VetVisitEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: VetVisitStore, dueScheduler: DueReminderScheduler, cadenceMonths: Int, editing: VetVisit?) {
        _model = State(initialValue: VetVisitEditViewModel(store: store, dueScheduler: dueScheduler, cadenceMonths: cadenceMonths, editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visit") {
                    DatePicker("Date", selection: $model.occurredAt, displayedComponents: .date)
                    TextField("Clinic", text: $model.clinicName)
                    TextField("Vet", text: $model.vetName)
                    TextField("Reason", text: $model.reason)
                }
                Section("Outcome") {
                    TextField("Diagnosis", text: $model.diagnosis)
                    TextField("Treatment notes", text: $model.treatmentNotes)
                }
                Section("Next visit") {
                    Toggle("Schedule next visit", isOn: $model.hasNextVisit)
                    if model.hasNextVisit {
                        DatePicker("Next visit", selection: $model.nextVisitDate, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Save") {
                        Task {
                            try? await model.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Vet visit")
        }
    }
}
