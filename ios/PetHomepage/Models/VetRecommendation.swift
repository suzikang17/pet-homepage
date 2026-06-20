// ios/PetHomepage/Models/VetRecommendation.swift
import CoreData

@objc(VetRecommendation)
public class VetRecommendation: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var text: String
    @NSManaged public var vetVisit: VetVisit?
}

extension VetRecommendation {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<VetRecommendation> {
        NSFetchRequest<VetRecommendation>(entityName: "VetRecommendation")
    }
}
