// ios/PetHomepage/Models/Veterinarian.swift
import CoreData

@objc(Veterinarian)
public class Veterinarian: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var clinic: String?
    @NSManaged public var phone: String?
    @NSManaged public var email: String?
    @NSManaged public var address: String?
    @NSManaged public var website: String?
    @NSManaged public var notes: String?
    @NSManaged public var pet: Pet?
    @NSManaged public var vetVisits: NSSet?
    @NSManaged public var vaccinations: NSSet?
    @NSManaged public var medications: NSSet?
}

extension Veterinarian {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Veterinarian> {
        NSFetchRequest<Veterinarian>(entityName: "Veterinarian")
    }
}
