// ios/PetHomepage/Models/RoutineSkip.swift
import CoreData

/// Deviation record: "this routine task is deliberately skipped on this day." Existence is the
/// whole signal — un-skipping deletes the record. Keyed by the task's lineageID (stable across
/// template versions) and a day-granular date.
@objc(RoutineSkip)
public class RoutineSkip: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var taskLineageID: UUID
    @NSManaged public var pet: Pet?
}

extension RoutineSkip {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<RoutineSkip> {
        NSFetchRequest<RoutineSkip>(entityName: "RoutineSkip")
    }
}

extension RoutineSkip: Identifiable {}
