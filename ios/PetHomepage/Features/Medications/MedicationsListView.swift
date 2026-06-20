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
            BrandList(title: "Medications", subtitle: "Meds",
                      systemImage: "pills.fill", onAdd: { showingAdd = true }) {
                if model.rows.isEmpty {
                    Text("No medications yet. Tap + to add one.")
                        .font(Theme.body()).foregroundStyle(Theme.inkSoft)
                        .brandRow()
                }
                ForEach(model.rows) { row in
                    medRow(row)
                        .brandRow()
                        .contentShape(Rectangle())
                        .onTapGesture { editing = row.medication }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
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

    @ViewBuilder
    private func medRow(_ row: MedicationRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.drugName).font(Theme.headline()).foregroundStyle(Theme.ink)
                Spacer()
                Button("Log dose") { Task { try? await model.logDose(row) } }
                    .buttonStyle(.borderless)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.primary)
            }
            if !row.dosage.isEmpty {
                Text(row.dosage).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            Text(lastGivenText(row.lastGiven)).font(.caption).foregroundStyle(Theme.inkSoft)
            if let nextDue = row.nextDue {
                Text("Next: \(nextDue.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            if let refill = row.refillDueAt {
                Text("Refill due \(refill.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.isRefillDueSoon ? Theme.warn : Theme.inkSoft)
            }
        }
    }

    private func lastGivenText(_ date: Date?) -> String {
        guard let date else { return "Never given" }
        return "Last given \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension Medication: Identifiable {}
