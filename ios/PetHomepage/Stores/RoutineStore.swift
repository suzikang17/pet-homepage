// ios/PetHomepage/Stores/RoutineStore.swift
import CoreData

/// The versioned weekly care template + per-day deviations, pet-scoped. A day's checklist is
/// COMPUTED from the template rows in effect on that date (see slots(for:)) — days are never
/// materialized, so CloudKit sync can't double-create them. Only deviations are stored:
/// completions (LogEntry kind .routine), skips (RoutineSkip), and one-off tasks (single-day
/// RoutineTask windows).
final class RoutineStore {
    let context: NSManagedObjectContext
    let petStore: PetStore
    let calendar: Calendar

    init(context: NSManagedObjectContext, petStore: PetStore, calendar: Calendar = .current) {
        self.context = context
        self.petStore = petStore
        self.calendar = calendar
    }

    // MARK: - Template CRUD (versioned)

    @discardableResult
    func createTask(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    hour: Int,
                    minute: Int,
                    weekdayMask: Int64,
                    from day: Date = Date()) throws -> RoutineTask {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = category
        task.iconName = iconName
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = weekdayMask
        task.effectiveFrom = calendar.startOfDay(for: day)
        task.effectiveUntil = nil
        task.isOneOff = false
        task.sortOrder = Int64(try currentTasks().count)
        task.pet = try petStore.ensurePet()
        try context.save()
        return task
    }

    /// The open-ended template rows (the "current routine" the editor shows). One-offs excluded.
    func currentTasks() throws -> [RoutineTask] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND effectiveUntil == nil AND isOneOff == NO", pet)
        return try context.fetch(request).sorted(by: Self.byTime)
    }

    /// Versioned edit: close the current row as of `day` and spawn a successor sharing its
    /// lineageID, so past days keep computing against the old version. A row that only became
    /// effective today (or a one-off) has no history to preserve — it's edited in place.
    @discardableResult
    func editTask(_ task: RoutineTask,
                  name: String,
                  category: ActivityCategory,
                  iconName: String,
                  hour: Int,
                  minute: Int,
                  weekdayMask: Int64,
                  on day: Date = Date()) throws -> RoutineTask {
        let today = calendar.startOfDay(for: day)
        if task.effectiveFrom >= today || task.isOneOff {
            task.name = name
            task.category = category
            task.iconName = iconName
            task.hour = Int64(hour)
            task.minute = Int64(minute)
            task.weekdayMask = weekdayMask
            try context.save()
            return task
        }
        task.effectiveUntil = today
        let successor = RoutineTask(context: context)
        successor.id = UUID()
        successor.lineageID = task.lineageID
        successor.name = name
        successor.category = category
        successor.iconName = iconName
        successor.hour = Int64(hour)
        successor.minute = Int64(minute)
        successor.weekdayMask = weekdayMask
        successor.effectiveFrom = today
        successor.effectiveUntil = nil
        successor.isOneOff = false
        successor.sortOrder = task.sortOrder
        successor.pet = task.pet
        try context.save()
        return successor
    }

    /// "Delete" = close the window as of `day`; past days keep the task. A row that never
    /// applied to a past day (created today, or a one-off) is genuinely deleted.
    func endTask(_ task: RoutineTask, on day: Date = Date()) throws {
        let today = calendar.startOfDay(for: day)
        if task.effectiveFrom >= today || task.isOneOff {
            context.delete(task)
        } else {
            task.effectiveUntil = today
        }
        try context.save()
    }

    // MARK: - One-offs

    /// A task for a single day only: a template row whose effective window covers exactly `day`.
    @discardableResult
    func addOneOff(name: String,
                   category: ActivityCategory,
                   iconName: String,
                   hour: Int,
                   minute: Int,
                   on day: Date) throws -> RoutineTask {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw NSError(domain: "RoutineStore", code: 1)
        }
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = category
        task.iconName = iconName
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = Weekdays.bit(for: calendar.component(.weekday, from: start))
        task.effectiveFrom = start
        task.effectiveUntil = end
        task.isOneOff = true
        task.sortOrder = 0
        task.pet = try petStore.ensurePet()
        try context.save()
        return task
    }

    /// Time-of-day sort shared by the template list and day slots.
    static func byTime(_ l: RoutineTask, _ r: RoutineTask) -> Bool {
        if l.hour != r.hour { return l.hour < r.hour }
        if l.minute != r.minute { return l.minute < r.minute }
        if l.sortOrder != r.sortOrder { return l.sortOrder < r.sortOrder }
        return l.name < r.name
    }
}
