// ios/PetHomepage/Models/VetVisit.swift
import CoreData

@objc(VetVisit)
public class VetVisit: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var occurredAt: Date?
    @NSManaged public var clinicName: String?
    @NSManaged public var vetName: String?
    @NSManaged public var reason: String?
    @NSManaged public var diagnosis: String?
    @NSManaged public var treatmentNotes: String?
    @NSManaged public var nextVisitDate: Date?
    @NSManaged public var pet: Pet?
    @NSManaged public var recommendations: NSSet?
}

extension VetVisit {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<VetVisit> {
        NSFetchRequest<VetVisit>(entityName: "VetVisit")
    }
}
