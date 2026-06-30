// ios/PetHomepage/Models/ActivityType.swift
import CoreData

@objc(ActivityType)
public class ActivityType: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var iconName: String
    @NSManaged public var defaultIntervalDays: Int64
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isArchived: Bool
    @NSManaged public var pet: Pet?
    @NSManaged public var logs: NSSet?
}

extension ActivityType {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<ActivityType> {
        NSFetchRequest<ActivityType>(entityName: "ActivityType")
    }

    /// Strongly-typed view of `categoryRaw`; falls back to `.other` for unknown values.
    var category: ActivityCategory {
        get { ActivityCategory(rawValueOrOther: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }
}

extension ActivityType: Identifiable {}
