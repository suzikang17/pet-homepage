// ios/PetHomepage/Features/VetVisits/VetVisitEditViewModel.swift
import Foundation
import Observation

@Observable
final class VetVisitEditViewModel {
    var occurredAt: Date = Date()
    var clinicName: String = ""
    var vetName: String = ""
    var reason: String = ""
    var diagnosis: String = ""
    var treatmentNotes: String = ""
    var hasNextVisit: Bool = false
    var nextVisitDate: Date = Date()
    var availableVets: [Veterinarian] = []
    var selectedVet: Veterinarian?

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler
    private let cadenceMonths: Int
    private let editing: LogEntry?

    init(logStore: LogStore, dueScheduler: DueReminderScheduler, cadenceMonths: Int,
         veterinarianStore: VeterinarianStore, editing: LogEntry?) {
        self.logStore = logStore
        self.dueScheduler = dueScheduler
        self.cadenceMonths = cadenceMonths
        self.editing = editing
        if let visit = editing {
            occurredAt = visit.performedAt
            clinicName = visit.clinicName ?? ""
            vetName = visit.vetName ?? ""
            reason = visit.title ?? ""
            diagnosis = visit.diagnosis ?? ""
            treatmentNotes = visit.treatmentNotes ?? ""
            if let next = visit.nextDueAt {
                hasNextVisit = true
                nextVisitDate = next
            }
        }
        availableVets = (try? veterinarianStore.veterinarians()) ?? []
        selectedVet = editing?.veterinarian
    }

    var isValid: Bool { true } // occurredAt always set; other fields optional

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    func save() async throws {
        let next = hasNextVisit ? nextVisitDate : nil
        let visit: LogEntry
        if let existing = editing {
            try logStore.updateVetVisit(existing, occurredAt: occurredAt,
                             clinicName: nilIfEmpty(clinicName), vetName: nilIfEmpty(vetName),
                             reason: nilIfEmpty(reason), diagnosis: nilIfEmpty(diagnosis),
                             treatmentNotes: nilIfEmpty(treatmentNotes), nextVisitDate: next)
            visit = existing
        } else {
            visit = try logStore.logVetVisit(occurredAt: occurredAt,
                             clinicName: nilIfEmpty(clinicName), vetName: nilIfEmpty(vetName),
                             reason: nilIfEmpty(reason), diagnosis: nilIfEmpty(diagnosis),
                             treatmentNotes: nilIfEmpty(treatmentNotes), nextVisitDate: next)
        }
        visit.veterinarian = selectedVet
        try? visit.managedObjectContext?.save()
        // Saving a visit changes "most recent visit" → re-sync the cadence reminder.
        let lastVisit = try? logStore.mostRecentVisitDate()
        await dueScheduler.syncVetCadence(
            lastVisit: lastVisit,
            cadence: VetCadence(months: cadenceMonths, hour: 9, minute: 0)
        )
    }
}
