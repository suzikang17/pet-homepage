// ios/PetHomepage/Stores/RoutineStore.swift
import CoreData

/// One row of a day's checklist: the template task in effect that day plus its per-day state.
/// Identity is the lineageID — stable across template versions, unique within a day.
struct RoutineSlot: Identifiable {
    let task: RoutineTask
    let completion: LogEntry?
    let skip: RoutineSkip?
    /// A "this day only" time change; nil = the template time applies.
    let timeOverride: RoutineOverride?
    /// For meal slots: every feeding logged this day (oldest first). Empty for non-meals.
    let feedings: [LogEntry]

    init(task: RoutineTask, completion: LogEntry?, skip: RoutineSkip?,
         timeOverride: RoutineOverride? = nil, feedings: [LogEntry] = []) {
        self.task = task
        self.completion = completion
        self.skip = skip
        self.timeOverride = timeOverride
        self.feedings = feedings
    }

    var id: UUID { task.lineageID }
    /// Behaves as a meal only once it has an allotment — a meal-flagged slot with no target
    /// stays an ordinary single check-off (so feeding-named seeds keep working until configured).
    var isMeal: Bool { task.isMeal && task.mealAllotment > 0 }
    var isSkipped: Bool { skip != nil }

    /// Total amount fed this day (sum of feeding values). 0 for non-meal slots.
    var fedTotal: Double { feedings.reduce(0) { $0 + $1.value } }

    /// A meal slot completes when its feedings reach the allotment; every other slot
    /// completes when it has a completion entry.
    var isCompleted: Bool {
        if isMeal { return task.mealAllotment > 0 && fedTotal >= task.mealAllotment }
        return completion != nil
    }

    /// Ring fill for meal slots, 0…1.
    var mealProgress: Double {
        guard isMeal, task.mealAllotment > 0 else { return 0 }
        return min(1, fedTotal / task.mealAllotment)
    }

    /// The time this slot is due on its day — the override's when one exists, else the template's.
    var hour: Int { timeOverride.map { Int($0.hour) } ?? Int(task.hour) }
    var minute: Int { timeOverride.map { Int($0.minute) } ?? Int(task.minute) }
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

    /// The editor's default for "counts as a walk" while typing; nil `isWalk` params fall
    /// back to this so walk-named tasks are matchable without any manual toggling.
    static func inferIsWalk(name: String) -> Bool {
        name.localizedCaseInsensitiveContains("walk")
    }

    /// Default for "counts as a meal" while typing: feeding-shaped names.
    static func inferIsMeal(name: String) -> Bool {
        let n = name.lowercased()
        return ["meal", "breakfast", "lunch", "dinner", "feed", "food", "snack"]
            .contains { n.contains($0) }
    }

    @discardableResult
    func createTask(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    hour: Int,
                    minute: Int,
                    weekdayMask: Int64,
                    isWalk: Bool? = nil,
                    isMeal: Bool? = nil,
                    mealAllotment: Double = 0,
                    mealUnit: String? = nil,
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
        task.isWalk = isWalk ?? Self.inferIsWalk(name: name)
        task.isMeal = isMeal ?? Self.inferIsMeal(name: name)
        task.mealAllotment = mealAllotment
        task.mealUnit = mealUnit
        task.effectiveFrom = calendar.startOfDay(for: day)
        task.effectiveUntil = nil
        task.isOneOff = false
        task.sortOrder = Int64(try currentTasks().count)
        task.pet = try petStore.ensurePet()
        try context.save()
        return task
    }

    /// One-time backfill for rows created before `isWalk` existed: marks tasks whose name
    /// contains "walk", or whose play/training category carries the figure.walk icon. Run
    /// once (the caller guards with a defaults flag) so a user who later opts a task out is
    /// never re-flipped.
    func backfillWalkFlags() throws {
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "isWalk == NO")
        var changed = false
        for task in try context.fetch(request) {
            let walkShaped = (task.category == .play || task.category == .training)
                && task.iconName == "figure.walk"
            if Self.inferIsWalk(name: task.name) || walkShaped {
                task.isWalk = true
                changed = true
            }
        }
        if changed { try context.save() }
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
                  isWalk: Bool? = nil,
                  isMeal: Bool? = nil,
                  mealAllotment: Double? = nil,
                  mealUnit: String? = nil,
                  on day: Date = Date()) throws -> RoutineTask {
        let today = calendar.startOfDay(for: day)
        if task.effectiveFrom >= today || task.isOneOff {
            task.name = name
            task.category = category
            task.iconName = iconName
            task.hour = Int64(hour)
            task.minute = Int64(minute)
            task.weekdayMask = weekdayMask
            task.isWalk = isWalk ?? task.isWalk
            task.isMeal = isMeal ?? task.isMeal
            if let mealAllotment { task.mealAllotment = mealAllotment }
            if let mealUnit { task.mealUnit = mealUnit }
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
        successor.isWalk = isWalk ?? task.isWalk
        successor.isMeal = isMeal ?? task.isMeal
        successor.mealAllotment = mealAllotment ?? task.mealAllotment
        successor.mealUnit = mealUnit ?? task.mealUnit
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
                   isWalk: Bool? = nil,
                   isMeal: Bool? = nil,
                   mealAllotment: Double = 0,
                   mealUnit: String? = nil,
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
        task.isWalk = isWalk ?? Self.inferIsWalk(name: name)
        task.isMeal = isMeal ?? Self.inferIsMeal(name: name)
        task.mealAllotment = mealAllotment
        task.mealUnit = mealUnit
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

        let completionRequest = LogEntry.fetchRequest()
        completionRequest.predicate = NSPredicate(
            format: "pet == %@ AND kindRaw == %@ AND performedAt >= %@ AND performedAt < %@",
            pet, LogKind.routine.rawValue, start as NSDate, end as NSDate)
        var completions: [UUID: LogEntry] = [:]
        var feedingsByLineage: [UUID: [LogEntry]] = [:]
        for entry in try context.fetch(completionRequest) {
            guard let lineage = entry.routineLineageID else { continue }
            completions[lineage] = entry
            feedingsByLineage[lineage, default: []].append(entry)
        }
        for lineage in feedingsByLineage.keys {
            feedingsByLineage[lineage]?.sort { $0.performedAt < $1.performedAt }
        }

        let skipRequest = RoutineSkip.fetchRequest()
        skipRequest.predicate = NSPredicate(format: "pet == %@ AND date == %@", pet, start as NSDate)
        var skips: [UUID: RoutineSkip] = [:]
        for skip in try context.fetch(skipRequest) {
            skips[skip.taskLineageID] = skip
        }

        let overrideRequest = RoutineOverride.fetchRequest()
        overrideRequest.predicate = NSPredicate(format: "pet == %@ AND date == %@", pet, start as NSDate)
        var overrides: [UUID: RoutineOverride] = [:]
        for override in try context.fetch(overrideRequest) {
            overrides[override.taskLineageID] = override
        }

        // Sort by each slot's EFFECTIVE time (a "this day only" override moves the row).
        return tasks
            .map {
                RoutineSlot(task: $0, completion: completions[$0.lineageID],
                            skip: skips[$0.lineageID], timeOverride: overrides[$0.lineageID],
                            feedings: $0.isMeal ? (feedingsByLineage[$0.lineageID] ?? []) : [])
            }
            .sorted { l, r in
                if l.hour != r.hour { return l.hour < r.hour }
                if l.minute != r.minute { return l.minute < r.minute }
                if l.task.sortOrder != r.task.sortOrder { return l.task.sortOrder < r.task.sortOrder }
                return l.task.name < r.task.name
            }
    }

    // MARK: - Skips

    /// Marks the task's lineage as deliberately skipped on `day`. Idempotent. Attaches to the
    /// task's own pet (not the active pet) so notification actions work for any pet's task.
    func skip(_ task: RoutineTask, on day: Date) throws {
        guard try skipRecord(lineageID: task.lineageID, on: day) == nil else { return }
        let skip = RoutineSkip(context: context)
        skip.id = UUID()
        skip.date = calendar.startOfDay(for: day)
        skip.taskLineageID = task.lineageID
        skip.pet = try task.pet ?? petStore.ensurePet()
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

    // MARK: - Time overrides ("this day only")

    /// Moves the task to a different time on `day` only. Upserts: overriding twice replaces
    /// the previous override. The template and every other day are untouched.
    func overrideTime(_ task: RoutineTask, on day: Date, hour: Int, minute: Int) throws {
        let record = try overrideRecord(lineageID: task.lineageID, on: day) ?? {
            let fresh = RoutineOverride(context: context)
            fresh.id = UUID()
            fresh.date = calendar.startOfDay(for: day)
            fresh.taskLineageID = task.lineageID
            fresh.pet = task.pet
            return fresh
        }()
        if record.pet == nil { record.pet = try petStore.ensurePet() }
        record.hour = Int64(hour)
        record.minute = Int64(minute)
        try context.save()
    }

    /// Removes the day's time change, restoring the template time.
    func clearOverrideTime(_ task: RoutineTask, on day: Date) throws {
        guard let record = try overrideRecord(lineageID: task.lineageID, on: day) else { return }
        context.delete(record)
        try context.save()
    }

    private func overrideRecord(lineageID: UUID, on day: Date) throws -> RoutineOverride? {
        let start = calendar.startOfDay(for: day)
        let request = RoutineOverride.fetchRequest()
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
    func checkOff(_ task: RoutineTask, on day: Date, now: Date = Date(),
                  startedAt: Date? = nil, endedAt: Date? = nil) throws -> LogEntry {
        let start = calendar.startOfDay(for: day)
        let performedAt: Date
        if calendar.isDate(now, inSameDayAs: start) {
            performedAt = now
        } else {
            // Past-day check-off stamps the day's effective time — the override's if that day
            // had a "this day only" time change, else the template's.
            let override = try overrideRecord(lineageID: task.lineageID, on: start)
            let hour = override.map { Int($0.hour) } ?? Int(task.hour)
            let minute = override.map { Int($0.minute) } ?? Int(task.minute)
            performedAt = calendar.date(bySettingHour: hour, minute: minute,
                                        second: 0, of: start) ?? start
        }
        let entry = LogEntry(context: context)
        entry.id = UUID()
        // A walk session supplies the real start; endedAt is stored only when it's a valid span.
        entry.performedAt = startedAt ?? performedAt
        if let endedAt, endedAt >= entry.performedAt { entry.endedAt = endedAt }
        entry.kind = .routine
        entry.title = task.name
        entry.routineLineageID = task.lineageID
        // The task's own pet, not the active pet: a notification action can complete a
        // non-active pet's task.
        entry.pet = try task.pet ?? petStore.ensurePet()
        try context.save()
        return entry
    }

    /// Logs one feeding of a meal slot: a routine LogEntry carrying the amount (`value`) in
    /// the slot's unit. Never dedupes — a meal is logged as many times as the pet eats.
    @discardableResult
    func logFeeding(_ task: RoutineTask, on day: Date, now: Date = Date(),
                    amount: Double) throws -> LogEntry {
        let start = calendar.startOfDay(for: day)
        let performedAt: Date
        if calendar.isDate(now, inSameDayAs: start) {
            performedAt = now
        } else {
            let override = try overrideRecord(lineageID: task.lineageID, on: start)
            let hour = override.map { Int($0.hour) } ?? Int(task.hour)
            let minute = override.map { Int($0.minute) } ?? Int(task.minute)
            performedAt = calendar.date(bySettingHour: hour, minute: minute,
                                        second: 0, of: start) ?? start
        }
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = performedAt
        entry.kind = .routine
        entry.title = task.name
        entry.routineLineageID = task.lineageID
        entry.value = amount
        entry.unit = task.mealUnit
        entry.pet = try task.pet ?? petStore.ensurePet()
        try context.save()
        return entry
    }

    /// Every routine completion for this task on `day`, oldest first (meal slots have many).
    func completions(of task: RoutineTask, on day: Date) throws -> [LogEntry] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "kindRaw == %@ AND routineLineageID == %@ AND performedAt >= %@ AND performedAt < %@",
            LogKind.routine.rawValue, task.lineageID as CVarArg, start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Total amount fed for a meal slot on `day`.
    func fedTotal(of task: RoutineTask, on day: Date) throws -> Double {
        try completions(of: task, on: day).reduce(0) { $0 + $1.value }
    }

    /// The completion entry for this task on `day`, if any. Pet-independent (keyed by lineage),
    /// so notification actions can dedupe without relying on the active-pet scope.
    func completion(of task: RoutineTask, on day: Date) throws -> LogEntry? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "kindRaw == %@ AND routineLineageID == %@ AND performedAt >= %@ AND performedAt < %@",
            LogKind.routine.rawValue, task.lineageID as CVarArg, start as NSDate, end as NSDate)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Moves a completion within its day (the "I actually did this at 7:40" edit). The day is
    /// pinned — only the time-of-day changes, so the entry stays on its slot.
    func updateCompletionTime(_ completion: LogEntry, hour: Int, minute: Int) throws {
        let day = calendar.startOfDay(for: completion.performedAt)
        completion.performedAt = calendar.date(bySettingHour: hour, minute: minute,
                                               second: 0, of: day) ?? completion.performedAt
        try context.save()
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
