// ios/PetHomepage/Models/Photo.swift
import CoreData

@objc(Photo)
public class Photo: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data?
    @NSManaged public var caption: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var pet: Pet?
    @NSManaged public var diaryEntry: DiaryEntry?
    @NSManaged public var vetVisit: VetVisit?
    @NSManaged public var medication: Medication?
    @NSManaged public var vaccination: Vaccination?
    @NSManaged public var activityLog: ActivityLog?
}

extension Photo {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Photo> {
        NSFetchRequest<Photo>(entityName: "Photo")
    }
}

extension Photo: Identifiable {}
