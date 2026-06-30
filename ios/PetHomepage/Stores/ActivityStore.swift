// ios/PetHomepage/Stores/ActivityStore.swift
import CoreData

/// CRUD for user-defined activity types and their logged occurrences, scoped to the single
/// current pet (v1). Mirrors HealthMarkerStore / VaccinationStore. Reminder scheduling is NOT
/// done here — the edit ViewModel calls DueReminderScheduler after the store saves.
final class ActivityStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore
    private let calendar: Calendar

    init(context: NSManagedObjectContext, petStore: PetStore, calendar: Calendar = .current) {
        self.context = context
        self.petStore = petStore
        self.calendar = calendar
    }

    // MARK: - Types

    @discardableResult
    func createType(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int) throws -> ActivityType {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        type.sortOrder = Int64(try types(includeArchived: true).count)
        type.isArchived = false
        type.pet = try petStore.ensurePet()
        try context.save()
        return type
    }

    /// Activity types for the current pet, sorted by category then sortOrder then name.
    func types(includeArchived: Bool = false) throws -> [ActivityType] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = ActivityType.fetchRequest()
        request.predicate = includeArchived
            ? NSPredicate(format: "pet == %@", pet)
            : NSPredicate(format: "pet == %@ AND isArchived == NO", pet)
        let all = try context.fetch(request)
        return all.sorted { lhs, rhs in
            if lhs.category.displayName != rhs.category.displayName {
                return lhs.category.displayName < rhs.category.displayName
            }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    func updateType(_ type: ActivityType,
                    name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int) throws {
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        try context.save()
    }

    func archiveType(_ type: ActivityType) throws {
        type.isArchived = true
        try context.save()
    }

    // MARK: - Logs

    @discardableResult
    func log(type: ActivityType,
             performedAt: Date,
             note: String?,
             intervalDays: Int) throws -> ActivityLog {
        let log = ActivityLog(context: context)
        log.id = UUID()
        log.performedAt = performedAt
        log.note = note
        log.intervalDays = Int64(intervalDays)
        log.nextDueAt = intervalDays > 0
            ? calendar.date(byAdding: .day, value: intervalDays, to: performedAt)
            : nil
        log.activityType = type
        log.pet = try petStore.ensurePet()
        try context.save()
        return log
    }

    /// All logs for the current pet, most recent first.
    func logs() throws -> [ActivityLog] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        return try context.fetch(request)
    }

    func logs(of type: ActivityType) throws -> [ActivityLog] {
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "activityType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        return try context.fetch(request)
    }

    func latestLog(of type: ActivityType) throws -> ActivityLog? {
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "activityType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func delete(_ log: ActivityLog) throws {
        context.delete(log)
        try context.save()
    }
}
