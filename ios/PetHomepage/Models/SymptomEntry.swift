// ios/PetHomepage/Models/SymptomEntry.swift
import CoreData

/// How bad the symptom was on a given day.
enum Severity: String, CaseIterable, Identifiable {
    case mild
    case moderate
    case severe

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Numeric rank (mild=1 … severe=3) for plotting / comparison.
    var rank: Int {
        switch self {
        case .mild: return 1
        case .moderate: return 2
        case .severe: return 3
        }
    }
}

@objc(SymptomEntry)
public class SymptomEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var severityRaw: String
    @NSManaged public var note: String?
    @NSManaged public var suspectedCause: String?
    @NSManaged public var episode: SymptomEpisode?
    @NSManaged public var logEntry: LogEntry?
}

extension SymptomEntry {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<SymptomEntry> {
        NSFetchRequest<SymptomEntry>(entityName: "SymptomEntry")
    }

    var severity: Severity {
        get { Severity(rawValue: severityRaw) ?? .mild }
        set { severityRaw = newValue.rawValue }
    }
}
