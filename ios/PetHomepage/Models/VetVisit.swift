// ios/PetHomepage/Models/VetVisit.swift
import CoreData

@objc(VetVisit)
public class VetVisit: NSManagedObject {
    /// The Core Data attribute is optional="YES" for CloudKit compatibility, but the store
    /// always assigns id = UUID() on create, so this non-optional declaration is safe.
    @NSManaged public var id: UUID
    /// The Core Data attribute is optional="YES" for CloudKit compatibility, but the store
    /// always assigns occurredAt on create, so this non-optional declaration is safe.
    @NSManaged public var occurredAt: Date
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
