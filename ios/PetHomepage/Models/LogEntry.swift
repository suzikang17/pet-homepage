// ios/PetHomepage/Models/LogEntry.swift
import CoreData

/// The kind of occurrence a LogEntry represents, derived from which definition it references.
enum LogKind { case diary, activity, dose }

/// A unified occurrence: a timestamped thing that happened, with an optional note + photos and an
/// optional reference to a definition. No reference = diary; activityType = activity log;
/// medication = dose log.
@objc(LogEntry)
public class LogEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var performedAt: Date
    @NSManaged public var note: String?
    @NSManaged public var intervalDays: Int64
    @NSManaged public var nextDueAt: Date?
    @NSManaged public var pet: Pet?
    @NSManaged public var activityType: ActivityType?
    @NSManaged public var medication: Medication?
    @NSManaged public var photos: NSSet?
}

extension LogEntry {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<LogEntry> {
        NSFetchRequest<LogEntry>(entityName: "LogEntry")
    }

    var kind: LogKind {
        if medication != nil { return .dose }
        if activityType != nil { return .activity }
        return .diary
    }

    /// This entry's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

extension LogEntry: Identifiable {}
