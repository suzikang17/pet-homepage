// ios/PetHomepage/Models/DiaryEntry.swift
import CoreData

@objc(DiaryEntry)
public class DiaryEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var note: String?
    @NSManaged public var pet: Pet?
    @NSManaged public var photos: NSSet?
}

extension DiaryEntry {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<DiaryEntry> {
        NSFetchRequest<DiaryEntry>(entityName: "DiaryEntry")
    }

    /// This entry's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

extension DiaryEntry: Identifiable {}
