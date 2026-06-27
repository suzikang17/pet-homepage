// ios/PetHomepage/Models/Medication.swift
import CoreData

@objc(Medication)
public class Medication: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var drugName: String
    @NSManaged public var dosage: String
    @NSManaged public var frequency: String
    @NSManaged public var scheduleTime: Date
    @NSManaged public var startedAt: Date
    @NSManaged public var endedAt: Date?
    @NSManaged public var refillDueAt: Date?
    @NSManaged public var pet: Pet?
    @NSManaged public var doseLogs: NSSet?
    @NSManaged public var veterinarian: Veterinarian?
    @NSManaged public var photos: NSSet?
}

extension Medication {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Medication> {
        NSFetchRequest<Medication>(entityName: "Medication")
    }

    /// This medication's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}
