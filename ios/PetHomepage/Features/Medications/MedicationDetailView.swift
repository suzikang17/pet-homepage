// ios/PetHomepage/Features/Medications/MedicationDetailView.swift
import SwiftUI

/// A medication's own page: its details + every logged dose, with one-tap dose logging.
/// "Edit" opens the MedicationEditView bottom sheet.
struct MedicationDetailView: View {
    @State private var model: MedicationDetailViewModel
    @State private var showEdit = false
    @State private var showLog = false
    @State private var photos: [Photo] = []
    private let services: TimelineServices

    init(medication: Medication, services: TimelineServices) {
        _model = State(initialValue: MedicationDetailViewModel(
            medication: medication,
            logStore: services.logStore,
            reminderScheduler: services.reminderScheduler
        ))
        self.services = services
    }

    private var med: Medication { model.medication }

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Dosage", value: med.dosage.isEmpty ? "—" : med.dosage)
                LabeledContent("Frequency", value: MedFrequency(parsing: med.frequency).label)
                if let vet = med.veterinarian {
                    LabeledContent("Veterinarian", value: vet.name)
                }
                LabeledContent("Next reminder") {
                    Text(med.nextReminder, format: .dateTime.month().day().year())
                }
                if let refill = med.refillDueAt {
                    LabeledContent("Refill due") { Text(refill, format: .dateTime.month().day().year()) }
                }
                if let ended = med.endedAt {
                    LabeledContent("Ended") { Text(ended, format: .dateTime.month().day().year()) }
                }
            }

            PhotoStripSection(
                photos: photos,
                onAdd: { try? services.diaryStore.addPhoto(toMedication: med, imageData: $0) },
                onDelete: { try? services.diaryStore.deletePhoto($0); photos = med.photoArray },
                onReload: { photos = med.photoArray }
            )

            Section("Doses (\(model.doseCount))") {
                Button {
                    showLog = true
                } label: {
                    Label("Log a dose", systemImage: "checkmark.circle.fill").fontWeight(.semibold)
                }
                if model.doses.isEmpty {
                    Text("No doses logged yet.").foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(model.doses, id: \.id) { dose in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.performedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Theme.ink)
                            if let note = dose.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.deleteDose(dose) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .brandSheet()
        .navigationTitle(med.drugName.isEmpty ? "Medication" : med.drugName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { photos = med.photoArray }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: { model.load() }) {
            MedicationEditView(store: services.medicationStore,
                               reminderScheduler: services.reminderScheduler,
                               veterinarianStore: services.veterinarianStore,
                               editing: med)
        }
        .sheet(isPresented: $showLog, onDismiss: { model.load() }) {
            LogDoseView(medication: med,
                        logStore: services.logStore,
                        reminderScheduler: services.reminderScheduler)
        }
    }
}
