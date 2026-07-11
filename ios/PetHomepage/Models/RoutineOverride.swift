// ios/PetHomepage/Models/RoutineOverride.swift
import CoreData

/// Deviation record: "this routine task runs at a different time on this one day." Same shape
/// as RoutineSkip — keyed by the task's lineageID (stable across template versions) and a
/// day-granular date. Removing the record restores the template time. Overriding a day does
/// NOT reschedule that day's already-pending notification (same accepted v1 limitation as skip).
@objc(RoutineOverride)
public class RoutineOverride: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var taskLineageID: UUID
    @NSManaged public var hour: Int64
    @NSManaged public var minute: Int64
    @NSManaged public var pet: Pet?
}

extension RoutineOverride {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<RoutineOverride> {
        NSFetchRequest<RoutineOverride>(entityName: "RoutineOverride")
    }
}

extension RoutineOverride: Identifiable {}
