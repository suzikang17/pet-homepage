// ios/PetHomepage/Features/VetVisits/VetVisitEditView.swift
import SwiftUI

struct VetVisitEditView: View {
    @State private var model: VetVisitEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(logStore: LogStore, dueScheduler: DueReminderScheduler, cadenceMonths: Int,
         veterinarianStore: VeterinarianStore, editing: LogEntry?) {
        _model = State(initialValue: VetVisitEditViewModel(logStore: logStore, dueScheduler: dueScheduler,
                                                           cadenceMonths: cadenceMonths,
                                                           veterinarianStore: veterinarianStore, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Vet visit",
            systemImage: "stethoscope",
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); dismiss() } }
        ) {
            Section("Visit") {
                DatePicker("Date", selection: $model.occurredAt, displayedComponents: .date)
                TextField("Clinic", text: $model.clinicName)
                TextField("Vet", text: $model.vetName)
                TextField("Reason", text: $model.reason)
            }
            VetPickerSection(vets: model.availableVets, selected: $model.selectedVet)
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
        }
    }
}
