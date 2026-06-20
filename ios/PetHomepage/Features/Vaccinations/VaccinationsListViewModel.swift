// ios/PetHomepage/Features/Vaccinations/VaccinationsListViewModel.swift
import Foundation
import Observation

struct VaccinationRow: Identifiable {
    let id: UUID
    let vaccination: Vaccination
    let vaccineName: String
    let lastGiven: Date?
    let nextDue: Date?
}

@Observable
final class VaccinationsListViewModel {
    var rows: [VaccinationRow] = []

    private let store: VaccinationStore
    private let dueScheduler: DueReminderScheduler

    init(store: VaccinationStore, dueScheduler: DueReminderScheduler) {
        self.store = store
        self.dueScheduler = dueScheduler
    }

    func load() throws {
        rows = try store.vaccinations().compactMap { vax in
            guard let id = vax.id else { return nil }
            return VaccinationRow(
                id: id,
                vaccination: vax,
                vaccineName: vax.vaccineName,
                lastGiven: try store.lastGiven(vaccineName: vax.vaccineName),
                nextDue: vax.nextDueAt
            )
        }
    }

    func delete(_ row: VaccinationRow) async throws {
        await dueScheduler.cancelVaccination(row.vaccination)
        try store.delete(row.vaccination)
        try load()
    }
}
