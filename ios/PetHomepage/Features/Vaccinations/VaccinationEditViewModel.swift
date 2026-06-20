// ios/PetHomepage/Features/Vaccinations/VaccinationEditViewModel.swift
import Foundation
import Observation

@Observable
final class VaccinationEditViewModel {
    var vaccineName: String = ""
    var administeredAt: Date = Date()
    var hasNextDue: Bool = false
    var nextDueAt: Date = Date()
    var lotNumber: String = ""
    var administeredBy: String = ""

    private let store: VaccinationStore
    private let dueScheduler: DueReminderScheduler
    private let editing: Vaccination?

    init(store: VaccinationStore, dueScheduler: DueReminderScheduler, editing: Vaccination?) {
        self.store = store
        self.dueScheduler = dueScheduler
        self.editing = editing
        if let vax = editing {
            vaccineName = vax.vaccineName
            administeredAt = vax.administeredAt ?? Date()
            if let due = vax.nextDueAt {
                hasNextDue = true
                nextDueAt = due
            }
            lotNumber = vax.lotNumber ?? ""
            administeredBy = vax.administeredBy ?? ""
        }
    }

    var isValid: Bool {
        !vaccineName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save() async throws {
        let due = hasNextDue ? nextDueAt : nil
        let lot = lotNumber.isEmpty ? nil : lotNumber
        let by = administeredBy.isEmpty ? nil : administeredBy

        let vaccination: Vaccination
        if let existing = editing {
            try store.update(existing, vaccineName: vaccineName, administeredAt: administeredAt,
                             nextDueAt: due, lotNumber: lot, administeredBy: by)
            vaccination = existing
        } else {
            vaccination = try store.create(vaccineName: vaccineName, administeredAt: administeredAt,
                                           nextDueAt: due, lotNumber: lot, administeredBy: by)
        }
        await dueScheduler.syncVaccination(vaccination)
    }
}
