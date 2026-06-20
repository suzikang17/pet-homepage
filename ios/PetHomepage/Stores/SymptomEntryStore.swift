// ios/PetHomepage/Stores/SymptomEntryStore.swift
import CoreData

/// Daily logs under a symptom episode. Each entry links to a parent SymptomEpisode.
/// Follows the VetRecommendationStore (parent-linked) pattern.
final class SymptomEntryStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func addEntry(to episode: SymptomEpisode,
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
        entry.episode = episode
        try context.save()
        return entry
    }

    /// Entries for an episode, oldest first (chronological daily log).
    func entries(for episode: SymptomEpisode) throws -> [SymptomEntry] {
        let request = SymptomEntry.fetchRequest()
        request.predicate = NSPredicate(format: "episode == %@", episode)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request)
    }

    /// The most-recent entry for an episode, or nil if none.
    func latestEntry(for episode: SymptomEpisode) throws -> SymptomEntry? {
        let request = SymptomEntry.fetchRequest()
        request.predicate = NSPredicate(format: "episode == %@", episode)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func delete(_ entry: SymptomEntry) throws {
        context.delete(entry)
        try context.save()
    }
}
