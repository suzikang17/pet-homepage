// ios/PetHomepage/Stores/RoutineStore.swift
import CoreData

/// One row of a day's checklist: the template task in effect that day plus its per-day state.
/// Identity is the lineageID — stable across template versions, unique within a day.
struct RoutineSlot: Identifiable {
    let task: RoutineTask
    let completion: LogEntry?
    let skip: RoutineSkip?

    var id: UUID { task.lineageID }
    var isCompleted: Bool { completion != nil }
    var isSkipped: Bool { skip != nil }
}

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

    // MARK: - Day computation

    /// The checklist for `day`, computed from template rows in effect on that date (weekday
    /// match + effective window), overlaid with that day's completions and skips. Pure read.
    func slots(for day: Date) throws -> [RoutineSlot] {
        guard let pet = try petStore.currentPet() else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)

        let taskRequest = RoutineTask.fetchRequest()
        taskRequest.predicate = NSPredicate(
            format: "pet == %@ AND effectiveFrom <= %@ AND (effectiveUntil == nil OR effectiveUntil > %@)",
            pet, start as NSDate, start as NSDate)
        let tasks = try context.fetch(taskRequest)
            .filter { Weekdays.contains($0.weekdayMask, weekday: weekday) }
            .sorted(by: Self.byTime)

        let completionRequest = LogEntry.fetchRequest()
        completionRequest.predicate = NSPredicate(
            format: "pet == %@ AND kindRaw == %@ AND performedAt >= %@ AND performedAt < %@",
            pet, LogKind.routine.rawValue, start as NSDate, end as NSDate)
        var completions: [UUID: LogEntry] = [:]
        for entry in try context.fetch(completionRequest) {
            if let lineage = entry.routineLineageID { completions[lineage] = entry }
        }

        let skipRequest = RoutineSkip.fetchRequest()
        skipRequest.predicate = NSPredicate(format: "pet == %@ AND date == %@", pet, start as NSDate)
        var skips: [UUID: RoutineSkip] = [:]
        for skip in try context.fetch(skipRequest) {
            skips[skip.taskLineageID] = skip
        }

        return tasks.map {
            RoutineSlot(task: $0, completion: completions[$0.lineageID], skip: skips[$0.lineageID])
        }
    }

    // MARK: - Skips

    /// Marks the task's lineage as deliberately skipped on `day`. Idempotent.
    func skip(_ task: RoutineTask, on day: Date) throws {
        guard try skipRecord(lineageID: task.lineageID, on: day) == nil else { return }
        let skip = RoutineSkip(context: context)
        skip.id = UUID()
        skip.date = calendar.startOfDay(for: day)
        skip.taskLineageID = task.lineageID
        skip.pet = try petStore.ensurePet()
        try context.save()
    }

    func unskip(_ task: RoutineTask, on day: Date) throws {
        guard let record = try skipRecord(lineageID: task.lineageID, on: day) else { return }
        context.delete(record)
        try context.save()
    }

    private func skipRecord(lineageID: UUID, on day: Date) throws -> RoutineSkip? {
        let start = calendar.startOfDay(for: day)
        let request = RoutineSkip.fetchRequest()
        request.predicate = NSPredicate(format: "taskLineageID == %@ AND date == %@",
                                        lineageID as CVarArg, start as NSDate)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Check-off

    /// Completing a slot writes a routine LogEntry with the task's name copied on, so later
    /// template edits never rewrite what was actually done. Today's check-off stamps `now`
    /// (the real moment); a past day's stamps the task's scheduled time on that day, keeping
    /// the entry inside that day's window.
    @discardableResult
    func checkOff(_ task: RoutineTask, on day: Date, now: Date = Date()) throws -> LogEntry {
        let start = calendar.startOfDay(for: day)
        let performedAt: Date
        if calendar.isDate(now, inSameDayAs: start) {
            performedAt = now
        } else {
            performedAt = calendar.date(bySettingHour: Int(task.hour), minute: Int(task.minute),
                                        second: 0, of: start) ?? start
        }
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = performedAt
        entry.kind = .routine
        entry.title = task.name
        entry.routineLineageID = task.lineageID
        entry.pet = try petStore.ensurePet()
        try context.save()
        return entry
    }

    /// Un-checking deletes the completion entry (photos cascade with it).
    func uncheck(_ completion: LogEntry) throws {
        context.delete(completion)
        try context.save()
    }

    // MARK: - Seeding

    /// The starter routine, pre-seeded so the Schedule tab works with zero setup. Training is
    /// deliberately Tue+Thu so the day-of-week feature is visible from minute one.
    static let defaultSeeds: [(name: String, category: ActivityCategory, iconName: String,
                               hour: Int, minute: Int, weekdayMask: Int64)] = [
        ("Breakfast", .feeding, "fork.knife", 7, 0, Weekdays.all),
        ("Morning walk", .play, "figure.walk", 8, 0, Weekdays.all),
        ("Training", .training, "graduationcap", 17, 0, Weekdays.mask(of: [3, 5])),
        ("Dinner", .feeding, "fork.knife", 18, 0, Weekdays.all),
        ("Wind down", .care, "moon.stars", 21, 0, Weekdays.all),
    ]

    /// Seeds any default tasks that don't already exist. De-dupes by case-insensitive name
    /// against ALL rows for the pet — including closed versions and rows synced in via CloudKit —
    /// so re-running never double-seeds and never resurrects a task the user deleted.
    func seedDefaultsIfNeeded() throws {
        guard let pet = try petStore.currentPet() else { return }
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        let existingNames = Set(try context.fetch(request).map { $0.name.lowercased() })
        for seed in Self.defaultSeeds where !existingNames.contains(seed.name.lowercased()) {
            try createTask(name: seed.name, category: seed.category, iconName: seed.iconName,
                           hour: seed.hour, minute: seed.minute, weekdayMask: seed.weekdayMask)
        }
    }

    /// Time-of-day sort shared by the template list and day slots.
    static func byTime(_ l: RoutineTask, _ r: RoutineTask) -> Bool {
        if l.hour != r.hour { return l.hour < r.hour }
        if l.minute != r.minute { return l.minute < r.minute }
        if l.sortOrder != r.sortOrder { return l.sortOrder < r.sortOrder }
        return l.name < r.name
    }
}
