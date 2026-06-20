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
            List {
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.vaccineName).font(.headline)
                        Text(lastText(row.lastGiven)).font(.caption).foregroundStyle(.secondary)
                        if let next = row.nextDue {
                            Text("Next due \(next.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = row.vaccination }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
                }
            }
            .navigationTitle("Vaccinations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
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

    private func lastText(_ date: Date?) -> String {
        guard let date else { return "Never given" }
        return "Last given \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

extension Vaccination: Identifiable {}
