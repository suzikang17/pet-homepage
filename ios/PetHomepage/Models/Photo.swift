// ios/PetHomepage/Models/Photo.swift
import CoreData

@objc(Photo)
public class Photo: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data?
    @NSManaged public var caption: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var pet: Pet?
    @NSManaged public var medication: Medication?
    @NSManaged public var logEntry: LogEntry?
}

extension Photo {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Photo> {
        NSFetchRequest<Photo>(entityName: "Photo")
    }
}

extension Photo: Identifiable {}
