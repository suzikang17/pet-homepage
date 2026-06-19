// ios/PetHomepage/Models/DoseLog.swift
import CoreData

@objc(DoseLog)
public class DoseLog: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var givenAt: Date
    @NSManaged public var medication: Medication?
}

extension DoseLog {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<DoseLog> {
        NSFetchRequest<DoseLog>(entityName: "DoseLog")
    }
}
