// ios/PetHomepage/Models/SymptomEpisode.swift
import CoreData

/// The kind of symptom an episode tracks.
enum SymptomCategory: String, CaseIterable, Identifiable {
    case digestive
    case skin
    case behavior
    case diet
    case energy
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// An episode is either ongoing (`active`) or closed (`resolved`).
enum EpisodeStatus: String {
    case active
    case resolved
}

@objc(SymptomEpisode)
public class SymptomEpisode: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var categoryRaw: String
    @NSManaged public var title: String?
    @NSManaged public var startedAt: Date
    @NSManaged public var resolvedAt: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var pet: Pet?
    @NSManaged public var entries: NSSet?
}

extension SymptomEpisode {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<SymptomEpisode> {
        NSFetchRequest<SymptomEpisode>(entityName: "SymptomEpisode")
    }

    var category: SymptomCategory {
        get { SymptomCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: EpisodeStatus {
        get { EpisodeStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}
