// ios/PetHomepage/Models/VetVisit.swift
import CoreData

@objc(VetVisit)
public class VetVisit: NSManagedObject {
    /// Core Data / CloudKit requires id to be optional="YES" in the model.
    /// Use `idValue` in application code — the store always sets id = UUID() on create.
    @NSManaged public var id: UUID?
    /// Core Data / CloudKit requires occurredAt to be optional="YES" in the model.
    /// Use `occurredAtValue` in application code — the store always writes a date on create.
    @NSManaged public var occurredAt: Date?
    @NSManaged public var clinicName: String?
    @NSManaged public var vetName: String?
    @NSManaged public var reason: String?
    @NSManaged public var diagnosis: String?
    @NSManaged public var treatmentNotes: String?
    @NSManaged public var nextVisitDate: Date?
    @NSManaged public var pet: Pet?
    @NSManaged public var recommendations: NSSet?

    /// Non-optional accessor. Traps if `id` is nil, which would indicate a store-level bug.
    public var idValue: UUID {
        guard let v = id else {
            preconditionFailure("VetVisit.id is nil — store must assign UUID on create")
        }
        return v
    }

    /// Non-optional accessor. Traps if `occurredAt` is nil, which would indicate a store-level bug.
    public var occurredAtValue: Date {
        guard let v = occurredAt else {
            preconditionFailure("VetVisit.occurredAt is nil — store must assign date on create")
        }
        return v
    }
}

extension VetVisit {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<VetVisit> {
        NSFetchRequest<VetVisit>(entityName: "VetVisit")
    }
}
