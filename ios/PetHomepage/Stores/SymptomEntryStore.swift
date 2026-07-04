// ios/PetHomepage/Stores/SymptomEntryStore.swift
import CoreData

/// Daily logs under a symptom occurrence. Each entry links to a parent `LogEntry` (kind
/// `.symptom`). Retargeted from `SymptomEpisode` to `LogEntry` — the legacy `episode`
/// relationship still exists on `SymptomEntry` but is never written by this store anymore.
/// Follows the VetRecommendationStore (parent-linked) pattern.
final class SymptomEntryStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func addEntry(to episode: LogEntry,
                  date: Date = Date(),
                  severity: Severity,
                  note: String?,
                  suspectedCause: String?) throws -> SymptomEntry {
        let entry = SymptomEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.severity = severity
        entry.note = note
        entry.suspectedCause = suspectedCause
        entry.logEntry = episode
        try context.save()
        return entry
    }

    /// Entries for an episode, oldest first (chronological daily log).
    func entries(for episode: LogEntry) throws -> [SymptomEntry] {
        let request = SymptomEntry.fetchRequest()
        request.predicate = NSPredicate(format: "logEntry == %@", episode)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request)
    }

    /// The most-recent entry for an episode, or nil if none.
    func latestEntry(for episode: LogEntry) throws -> SymptomEntry? {
        let request = SymptomEntry.fetchRequest()
        request.predicate = NSPredicate(format: "logEntry == %@", episode)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func delete(_ entry: SymptomEntry) throws {
        context.delete(entry)
        try context.save()
    }
}
