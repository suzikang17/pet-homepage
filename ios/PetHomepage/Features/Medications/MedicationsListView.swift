// ios/PetHomepage/Features/Medications/MedicationsListView.swift
import SwiftUI

struct MedicationsListView: View {
    @State private var model: MedicationsListViewModel
    @State private var showingAdd = false
    @State private var editing: Medication?

    private let medicationStore: MedicationStore
    private let reminderScheduler: MedicationReminderScheduler

    init(medicationStore: MedicationStore,
         doseLogStore: DoseLogStore,
         reminderScheduler: MedicationReminderScheduler) {
        self.medicationStore = medicationStore
        self.reminderScheduler = reminderScheduler
        _model = State(initialValue: MedicationsListViewModel(
            medicationStore: medicationStore,
            doseLogStore: doseLogStore,
            reminderScheduler: reminderScheduler
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.drugName).font(.headline)
                            Spacer()
                            Button("Log dose") {
                                Task { try? await model.logDose(row) }
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(row.dosage).font(.subheadline).foregroundStyle(.secondary)
                        Text(lastGivenText(row.lastGiven)).font(.caption).foregroundStyle(.secondary)
                        if let nextDue = row.nextDue {
                            Text("Next: \(nextDue.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let refill = row.refillDueAt {
                            Text("Refill due \(refill.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(row.isRefillDueSoon ? .orange : .secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = row.medication }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { try? model.load() }) {
                MedicationEditView(store: medicationStore,
                                   reminderScheduler: reminderScheduler,
                                   editing: nil)
            }
            .sheet(item: $editing, onDismiss: { try? model.load() }) { med in
                MedicationEditView(store: medicationStore,
                                   reminderScheduler: reminderScheduler,
                                   editing: med)
            }
            .onAppear { try? model.load() }
        }
    }

    private func lastGivenText(_ date: Date?) -> String {
        guard let date else { return "Never given" }
        return "Last given \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension Medication: Identifiable {}
