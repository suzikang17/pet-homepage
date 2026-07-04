// ios/PetHomepage/Stores/LogStore+Vaccine.swift
import CoreData

/// Vaccine occurrences: kind `.vaccine`, `title` = vaccine name, sparse `lotNumber`/`administeredBy`.
/// Mirrors the old VaccinationStore's shape (VaccinationStore itself is untouched; this replaces it
/// as the write path consumers use).
extension LogStore {
    @discardableResult
    func logVaccine(name: String,
                    performedAt: Date,
                    nextDueAt: Date?,
                    lotNumber: String?,
                    administeredBy: String?) throws -> LogEntry {
        let entry = try makeEntry(performedAt: performedAt, note: nil)
        entry.kind = .vaccine
        entry.title = name
        entry.nextDueAt = nextDueAt
        entry.lotNumber = lotNumber
        entry.administeredBy = administeredBy
        try context.save()
        return entry
    }

    func updateVaccine(_ entry: LogEntry,
                       name: String,
                       performedAt: Date,
                       nextDueAt: Date?,
                       lotNumber: String?,
                       administeredBy: String?) throws {
        entry.title = name
        entry.performedAt = performedAt
        entry.nextDueAt = nextDueAt
        entry.lotNumber = lotNumber
        entry.administeredBy = administeredBy
        try context.save()
    }

    /// All vaccine occurrences for the current pet, most recently performed first.
    func vaccines() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@", pet, LogKind.vaccine.rawValue))
    }
}
