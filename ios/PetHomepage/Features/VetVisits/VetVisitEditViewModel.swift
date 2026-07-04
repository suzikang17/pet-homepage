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
    var pendingPhotos: [Data] = []
    var existingPhotos: [Photo] = []

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler
    private let cadenceMonths: Int
    private let editing: LogEntry?

    init(logStore: LogStore, dueScheduler: DueReminderScheduler, cadenceMonths: Int,
         veterinarianStore: VeterinarianStore, editing: LogEntry?, initialPhoto: Data? = nil) {
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
        existingPhotos = editing?.photoArray ?? []
        // Capture handoff: a photo tagged "Vet visit" in the capture sheet arrives pre-staged
        // here (vet visits have required fields, so it can't instant-save from that sheet).
        if let initialPhoto {
            pendingPhotos.append(initialPhoto)
        }
    }

    var isValid: Bool { true } // occurredAt always set; other fields optional

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    func addPickedPhoto(_ data: Data) { pendingPhotos.append(data) }
    func removePending(at index: Int) {
        if pendingPhotos.indices.contains(index) { pendingPhotos.remove(at: index) }
    }
    func deleteExisting(_ photo: Photo) {
        try? logStore.deletePhoto(photo)
        existingPhotos.removeAll { $0 == photo }
    }

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
        for data in pendingPhotos {
            try? logStore.addPhoto(to: visit, imageData: data)
        }
        // Saving a visit changes "most recent visit" → re-sync the cadence reminder, keyed by
        // this visit's pet so it doesn't collide with another pet's cadence reminder.
        if let petID = visit.pet?.id {
            let lastVisit = try? logStore.mostRecentVisitDate()
            await dueScheduler.syncVetCadence(
                petID: petID,
                petName: visit.pet?.name,
                lastVisit: lastVisit,
                cadence: VetCadence(months: cadenceMonths, hour: 9, minute: 0)
            )
        }
        // else: no pet on the entry (shouldn't happen — LogStore always attaches one via
        // ensurePet()) — skip the sync rather than colliding with a shared sentinel.
    }
}
