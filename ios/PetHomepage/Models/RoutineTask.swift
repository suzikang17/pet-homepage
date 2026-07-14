// ios/PetHomepage/Models/RoutineTask.swift
import CoreData

/// Weekday-mask helpers shared by the routine template and its scheduler.
/// Calendar weekdays: 1 = Sunday … 7 = Saturday; a weekday's bit is `1 << (weekday - 1)`.
enum Weekdays {
    static let all: Int64 = 0b111_1111

    static func bit(for weekday: Int) -> Int64 { 1 << Int64(weekday - 1) }

    static func contains(_ mask: Int64, weekday: Int) -> Bool {
        mask & bit(for: weekday) != 0
    }

    static func mask(of weekdays: [Int]) -> Int64 {
        weekdays.reduce(0) { $0 | bit(for: $1) }
    }

    static func weekdays(in mask: Int64) -> [Int] {
        (1...7).filter { contains(mask, weekday: $0) }
    }
}

/// One versioned row of the weekly care template. Edits never mutate a row that has been in
/// effect before today — they close it (`effectiveUntil`) and spawn a successor sharing the same
/// `lineageID`, so past days forever compute against the template as it was then. A one-off task
/// for a single day is just a row whose window covers exactly that day (`isOneOff` flags it so
/// the template editor can hide it).
@objc(RoutineTask)
public class RoutineTask: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var lineageID: UUID
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var iconName: String
    @NSManaged public var hour: Int64
    @NSManaged public var minute: Int64
    @NSManaged public var weekdayMask: Int64
    @NSManaged public var effectiveFrom: Date
    @NSManaged public var effectiveUntil: Date?
    @NSManaged public var isOneOff: Bool
    /// Explicit "counts as a walk" marker: drives walk detection's slot attachment and
    /// end-of-walk matching. Set by the editor toggle (auto-inferred from the name) and a
    /// one-time backfill — never guessed at match time.
    @NSManaged public var isWalk: Bool
    @NSManaged public var sortOrder: Int64
    @NSManaged public var pet: Pet?
}

extension RoutineTask {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<RoutineTask> {
        NSFetchRequest<RoutineTask>(entityName: "RoutineTask")
    }

    /// Strongly-typed view of `categoryRaw`; falls back to `.other` for unknown values.
    var category: ActivityCategory {
        get { ActivityCategory(rawValueOrOther: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }
}

extension RoutineTask: Identifiable {}
