// ios/PetHomepage/Features/VetVisits/VetVisitsListViewModel.swift
import Foundation
import Observation

struct VetVisitRow: Identifiable {
    let id: UUID?
    let visit: VetVisit
    let occurredAt: Date?
    let clinicName: String?
    let reason: String?
}

@Observable
final class VetVisitsListViewModel {
    var rows: [VetVisitRow] = []

    private let store: VetVisitStore
    private let dueScheduler: DueReminderScheduler
    private let cadenceMonths: Int

    init(store: VetVisitStore, dueScheduler: DueReminderScheduler, cadenceMonths: Int) {
        self.store = store
        self.dueScheduler = dueScheduler
        self.cadenceMonths = cadenceMonths
    }

    func load() throws {
        rows = try store.visits().map { visit in
            VetVisitRow(id: visit.id, visit: visit, occurredAt: visit.occurredAt,
                        clinicName: visit.clinicName, reason: visit.reason)
        }
    }

    /// Re-schedule the "see vet every N months" reminder from the most recent visit.
    func syncCadence() async {
        let lastVisit = try? store.mostRecentVisitDate()
        await dueScheduler.syncVetCadence(
            lastVisit: lastVisit,
            cadence: VetCadence(months: cadenceMonths, hour: 9, minute: 0)
        )
    }

    func delete(_ row: VetVisitRow) async throws {
        try store.delete(row.visit)
        try load()
        await syncCadence()
    }
}
