// ios/PetHomepage/Models/VetRecommendation.swift
import CoreData

@objc(VetRecommendation)
public class VetRecommendation: NSManagedObject {
    /// The Core Data attribute is optional="YES" for CloudKit compatibility, but the store
    /// always assigns id = UUID() on create, so this non-optional declaration is safe.
    @NSManaged public var id: UUID
    /// The Core Data attribute is optional="YES" for CloudKit compatibility, but the store
    /// always assigns a date on create, so this non-optional declaration is safe.
    @NSManaged public var date: Date
    @NSManaged public var text: String
    @NSManaged public var logEntry: LogEntry?
}

extension VetRecommendation {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<VetRecommendation> {
        NSFetchRequest<VetRecommendation>(entityName: "VetRecommendation")
    }
}
