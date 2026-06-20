// ios/PetHomepage/Features/Vaccinations/VaccinationsListView.swift
import SwiftUI

struct VaccinationsListView: View {
    @State private var model: VaccinationsListViewModel
    @State private var showingAdd = false
    @State private var editing: Vaccination?

    private let store: VaccinationStore
    private let dueScheduler: DueReminderScheduler

    init(store: VaccinationStore, dueScheduler: DueReminderScheduler) {
        self.store = store
        self.dueScheduler = dueScheduler
        _model = State(initialValue: VaccinationsListViewModel(store: store, dueScheduler: dueScheduler))
    }

    var body: some View {
        NavigationStack {
            BrandList(title: "Vaccinations", subtitle: "Vaccines",
                      systemImage: "syringe.fill", onAdd: { showingAdd = true }) {
                if model.rows.isEmpty {
                    Text("No vaccinations yet. Tap + to add one.")
                        .font(Theme.body()).foregroundStyle(Theme.inkSoft)
                        .brandRow()
                }
                ForEach(model.rows) { row in
                    vaxRow(row)
                        .brandRow()
                        .contentShape(Rectangle())
                        .onTapGesture { editing = row.vaccination }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { try? model.load() }) {
                VaccinationEditView(store: store, dueScheduler: dueScheduler, editing: nil)
            }
            .sheet(item: $editing, onDismiss: { try? model.load() }) { vax in
                VaccinationEditView(store: store, dueScheduler: dueScheduler, editing: vax)
            }
            .onAppear { try? model.load() }
        }
    }

    @ViewBuilder
    private func vaxRow(_ row: VaccinationRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.vaccineName).font(Theme.headline()).foregroundStyle(Theme.ink)
            Text(lastText(row.lastGiven)).font(.caption).foregroundStyle(Theme.inkSoft)
            if let next = row.nextDue {
                Text("Next due \(next.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dueColor(next))
            }
        }
    }

    private func dueColor(_ date: Date) -> Color {
        let now = Date()
        if date < now { return Theme.danger }
        if date.timeIntervalSince(now) < 42 * 24 * 60 * 60 { return Theme.warn }
        return Theme.inkSoft
    }

    private func lastText(_ date: Date?) -> String {
        guard let date else { return "Never given" }
        return "Last given \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

extension Vaccination: Identifiable {}
