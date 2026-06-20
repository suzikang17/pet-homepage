// ios/PetHomepage/Models/Vaccination.swift
import CoreData

@objc(Vaccination)
public class Vaccination: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var vaccineName: String
    @NSManaged public var administeredAt: Date
    @NSManaged public var nextDueAt: Date?
    @NSManaged public var lotNumber: String?
    @NSManaged public var administeredBy: String?
    @NSManaged public var pet: Pet?
}

extension Vaccination {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Vaccination> {
        NSFetchRequest<Vaccination>(entityName: "Vaccination")
    }
}
