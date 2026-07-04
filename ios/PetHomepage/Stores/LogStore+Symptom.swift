// ios/PetHomepage/Stores/LogStore+Symptom.swift
import CoreData

/// Symptom occurrences: kind `.symptom`, `title` = episode title, `subtypeRaw` = `SymptomCategory`
/// raw value, `statusRaw` = `EpisodeStatus` raw value, `resolvedAt` set on resolve. Mirrors the old
/// SymptomEpisodeStore's shape (SymptomEpisodeStore itself is untouched; this replaces it as the
/// write path consumers use). `SymptomEntry` (the child daily-log rows) survives as an entity and
/// now retargets to this `LogEntry` via `SymptomEntryStore`.
extension LogEntry {
    /// Strongly-typed view of `subtypeRaw` for symptom entries; falls back to `.other` for unknown values.
    var category: SymptomCategory {
        get { SymptomCategory(rawValue: subtypeRaw ?? "") ?? .other }
        set { subtypeRaw = newValue.rawValue }
    }

    /// Strongly-typed view of `statusRaw` for symptom entries; falls back to `.active` for unknown values.
    var status: EpisodeStatus {
        get { EpisodeStatus(rawValue: statusRaw ?? "") ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

extension LogStore {
    @discardableResult
    func startEpisode(category: SymptomCategory,
                      title: String?,
                      startedAt: Date = Date()) throws -> LogEntry {
        let entry = try makeEntry(performedAt: startedAt, note: nil)
        entry.kind = .symptom
        entry.category = category
        entry.title = title
        entry.status = .active
        entry.resolvedAt = nil
        try context.save()
        return entry
    }

    func resolveEpisode(_ entry: LogEntry, at date: Date = Date()) throws {
        entry.status = .resolved
        entry.resolvedAt = date
        try context.save()
    }

    /// All symptom occurrences for the current pet, most recently started first.
    func episodes() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@", pet, LogKind.symptom.rawValue))
    }
}
