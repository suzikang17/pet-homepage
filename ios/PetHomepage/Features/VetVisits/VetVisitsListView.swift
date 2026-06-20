// ios/PetHomepage/Features/VetVisits/VetVisitsListView.swift
import SwiftUI

struct VetVisitsListView: View {
    @State private var model: VetVisitsListViewModel
    @State private var showingAdd = false
    @State private var editing: VetVisit?

    private let store: VetVisitStore
    private let recommendationStore: VetRecommendationStore
    private let dueScheduler: DueReminderScheduler
    private let cadenceMonths: Int

    init(store: VetVisitStore,
         recommendationStore: VetRecommendationStore,
         dueScheduler: DueReminderScheduler,
         cadenceMonths: Int) {
        self.store = store
        self.recommendationStore = recommendationStore
        self.dueScheduler = dueScheduler
        self.cadenceMonths = cadenceMonths
        _model = State(initialValue: VetVisitsListViewModel(store: store, dueScheduler: dueScheduler, cadenceMonths: cadenceMonths))
    }

    var body: some View {
        NavigationStack {
            BrandList(title: "Vet visits", subtitle: "Vet",
                      systemImage: "stethoscope", onAdd: { showingAdd = true }) {
                if model.rows.isEmpty {
                    Text("No vet visits yet. Tap + to add one.")
                        .font(Theme.body()).foregroundStyle(Theme.inkSoft)
                        .brandRow()
                }
                ForEach(model.rows) { row in
                    NavigationLink {
                        VetVisitDetailView(visit: row.visit,
                                           recommendationStore: recommendationStore)
                    } label: {
                        vetRow(row)
                    }
                    .brandRow()
                    .swipeActions(edge: .leading) {
                        Button("Edit") { editing = row.visit }.tint(Theme.primary)
                    }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                try? model.load()
                Task { await model.syncCadence() }
            }) {
                VetVisitEditView(store: store, dueScheduler: dueScheduler, cadenceMonths: cadenceMonths, editing: nil)
            }
            .sheet(item: $editing, onDismiss: {
                try? model.load()
                Task { await model.syncCadence() }
            }) { visit in
                VetVisitEditView(store: store, dueScheduler: dueScheduler, cadenceMonths: cadenceMonths, editing: visit)
            }
            .onAppear {
                try? model.load()
                Task { await model.syncCadence() }
            }
        }
    }

    @ViewBuilder
    private func vetRow(_ row: VetVisitRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.clinicName ?? "Vet visit").font(Theme.headline()).foregroundStyle(Theme.ink)
            Text(row.occurredAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(Theme.inkSoft)
            if let reason = row.reason {
                Text(reason).font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

extension VetVisit: Identifiable {}
