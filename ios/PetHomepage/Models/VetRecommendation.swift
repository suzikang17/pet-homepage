// ios/PetHomepage/Models/VetRecommendation.swift
import CoreData

@objc(VetRecommendation)
public class VetRecommendation: NSManagedObject {
    @NSManaged public var id: UUID?
    /// Core Data / CloudKit requires the backing attribute to be optional="YES".
    /// Use `dateValue` in application code — the store always writes a date on create.
    @NSManaged public var date: Date?
    @NSManaged public var text: String
    @NSManaged public var vetVisit: VetVisit?

    /// Non-optional accessor. Traps if `date` is nil, which would indicate a store-level bug.
    public var dateValue: Date {
        guard let d = date else {
            preconditionFailure("VetRecommendation.date is nil — store must assign date on create")
        }
        return d
    }
}

extension VetRecommendation {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<VetRecommendation> {
        NSFetchRequest<VetRecommendation>(entityName: "VetRecommendation")
    }
}
