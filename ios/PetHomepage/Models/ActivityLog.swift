// ios/PetHomepage/Models/ActivityLog.swift
import CoreData

@objc(ActivityLog)
public class ActivityLog: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var performedAt: Date
    @NSManaged public var note: String?
    @NSManaged public var intervalDays: Int64
    @NSManaged public var nextDueAt: Date?
    @NSManaged public var activityType: ActivityType?
    @NSManaged public var pet: Pet?
    @NSManaged public var photos: NSSet?
}

extension ActivityLog {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<ActivityLog> {
        NSFetchRequest<ActivityLog>(entityName: "ActivityLog")
    }

    /// This log's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

extension ActivityLog: Identifiable {}
