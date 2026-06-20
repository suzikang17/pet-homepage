// ios/PetHomepage/Features/VetVisits/VetVisitsListView.swift
import SwiftUI

struct VetVisitsListView: View {
    @State private var model: VetVisitsListViewModel
    @State private var showingAdd = false

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
            List {
                ForEach(model.rows) { row in
                    NavigationLink {
                        VetVisitDetailView(visit: row.visit,
                                           recommendationStore: recommendationStore)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.clinicName ?? "Vet visit").font(.headline)
                            Text((row.occurredAt ?? Date()).formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            if let reason = row.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.rows[$0] }
                    Task { for row in targets { try? await model.delete(row) } }
                }
            }
            .navigationTitle("Vet visits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                try? model.load()
                Task { await model.syncCadence() }
            }) {
                VetVisitEditView(store: store, dueScheduler: dueScheduler, cadenceMonths: cadenceMonths, editing: nil)
            }
            .onAppear {
                try? model.load()
                Task { await model.syncCadence() }
            }
        }
    }
}
