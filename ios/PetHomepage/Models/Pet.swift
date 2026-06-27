// ios/PetHomepage/Models/Pet.swift
import CoreData

@objc(Pet)
public class Pet: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var species: String
    @NSManaged public var breed: String?
    @NSManaged public var dob: Date?
    @NSManaged public var adoptionDate: Date?
    @NSManaged public var photoData: Data?
    @NSManaged public var medications: NSSet?
    @NSManaged public var veterinarians: NSSet?
}

extension Pet {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Pet> {
        NSFetchRequest<Pet>(entityName: "Pet")
    }
}
