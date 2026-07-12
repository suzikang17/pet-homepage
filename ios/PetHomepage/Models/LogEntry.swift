// ios/PetHomepage/Models/LogEntry.swift
import CoreData

/// The kind of occurrence a LogEntry represents, stored explicitly in `kindRaw`.
enum LogKind: String, CaseIterable, Identifiable {
    case diary
    case activity
    case dose
    case vaccine
    case vet
    case marker
    case symptom
    case routine

    var id: String { rawValue }
}

/// A unified occurrence: a timestamped thing that happened, with an optional note + photos and an
/// optional reference to a definition, plus sparse kind-specific columns (title, value, unit, etc.)
/// used by the record kinds (vaccine, vet, marker, symptom).
@objc(LogEntry)
public class LogEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var performedAt: Date
    @NSManaged public var note: String?
    @NSManaged public var intervalDays: Int64
    @NSManaged public var nextDueAt: Date?
    @NSManaged public var kindRaw: String
    @NSManaged public var title: String?
    @NSManaged public var subtypeRaw: String?
    @NSManaged public var value: Double
    @NSManaged public var unit: String?
    @NSManaged public var lotNumber: String?
    @NSManaged public var administeredBy: String?
    @NSManaged public var clinicName: String?
    @NSManaged public var vetName: String?
    @NSManaged public var diagnosis: String?
    @NSManaged public var treatmentNotes: String?
    @NSManaged public var statusRaw: String?
    @NSManaged public var resolvedAt: Date?
    @NSManaged public var endedAt: Date?
    @NSManaged public var routineLineageID: UUID?
    @NSManaged public var pet: Pet?
    @NSManaged public var activityType: ActivityType?
    @NSManaged public var medication: Medication?
    @NSManaged public var veterinarian: Veterinarian?
    @NSManaged public var photos: NSSet?
    @NSManaged public var recommendations: NSSet?
    @NSManaged public var symptomEntries: NSSet?
}

extension LogEntry {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<LogEntry> {
        NSFetchRequest<LogEntry>(entityName: "LogEntry")
    }

    /// Strongly-typed view of `kindRaw`; falls back to `.diary` for unknown values.
    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .diary }
        set { kindRaw = newValue.rawValue }
    }

    /// This entry's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Whole minutes between start and end, when this entry is a span.
    var durationMinutes: Int? {
        guard let endedAt else { return nil }
        return Int(endedAt.timeIntervalSince(performedAt) / 60)
    }
}

extension LogEntry: Identifiable {}
