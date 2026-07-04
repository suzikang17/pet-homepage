// ios/PetHomepage/Stores/LogStore+Vet.swift
import CoreData

/// Vet-visit occurrences: kind `.vet`, `title` = reason, sparse `clinicName`/`vetName`/
/// `diagnosis`/`treatmentNotes`. Mirrors the old VetVisitStore's shape (VetVisitStore itself is
/// untouched; this replaces it as the write path consumers use).
extension LogStore {
    @discardableResult
    func logVetVisit(occurredAt: Date,
                     clinicName: String?,
                     vetName: String?,
                     reason: String?,
                     diagnosis: String?,
                     treatmentNotes: String?,
                     nextVisitDate: Date?) throws -> LogEntry {
        let entry = try makeEntry(performedAt: occurredAt, note: nil)
        entry.kind = .vet
        entry.title = reason
        entry.clinicName = clinicName
        entry.vetName = vetName
        entry.diagnosis = diagnosis
        entry.treatmentNotes = treatmentNotes
        entry.nextDueAt = nextVisitDate
        try context.save()
        return entry
    }

    func updateVetVisit(_ entry: LogEntry,
                        occurredAt: Date,
                        clinicName: String?,
                        vetName: String?,
                        reason: String?,
                        diagnosis: String?,
                        treatmentNotes: String?,
                        nextVisitDate: Date?) throws {
        entry.performedAt = occurredAt
        entry.title = reason
        entry.clinicName = clinicName
        entry.vetName = vetName
        entry.diagnosis = diagnosis
        entry.treatmentNotes = treatmentNotes
        entry.nextDueAt = nextVisitDate
        try context.save()
    }

    /// All vet-visit occurrences for the current pet, most recently performed first.
    func vetVisits() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@", pet, LogKind.vet.rawValue))
    }

    /// The `performedAt` of the most recent vet visit, or nil — drives the vet-cadence reminder.
    func mostRecentVisitDate() throws -> Date? {
        try vetVisits().first?.performedAt
    }
}
