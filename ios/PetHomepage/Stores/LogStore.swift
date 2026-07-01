// ios/PetHomepage/Stores/LogStore.swift
import CoreData

/// Unified store for all logged occurrences (diary entries, activity logs, dose logs), pet-scoped.
/// Replaces the occurrence roles of DiaryStore/ActivityStore/DoseLogStore. Definitions
/// (ActivityType, Medication) live in their own stores. Reminder scheduling stays in the ViewModels.
final class LogStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore
    private let calendar: Calendar

    init(context: NSManagedObjectContext, petStore: PetStore, calendar: Calendar = .current) {
        self.context = context
        self.petStore = petStore
        self.calendar = calendar
    }

    // MARK: - Create

    @discardableResult
    func createDiary(performedAt: Date = Date(), note: String?) throws -> LogEntry {
        let entry = try makeEntry(performedAt: performedAt, note: note)
        try context.save()
        return entry
    }

    @discardableResult
    func logActivity(type: ActivityType, performedAt: Date, note: String?, intervalDays: Int) throws -> LogEntry {
        let entry = try makeEntry(performedAt: performedAt, note: note)
        entry.activityType = type
        entry.intervalDays = Int64(intervalDays)
        entry.nextDueAt = intervalDays > 0 ? calendar.date(byAdding: .day, value: intervalDays, to: performedAt) : nil
        try context.save()
        return entry
    }

    @discardableResult
    func logDose(for medication: Medication, at date: Date = Date(), note: String? = nil) throws -> LogEntry {
        let entry = try makeEntry(performedAt: date, note: note)
        entry.medication = medication
        try context.save()
        return entry
    }

    private func makeEntry(performedAt: Date, note: String?) throws -> LogEntry {
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = performedAt
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = (trimmed?.isEmpty == false) ? trimmed : nil
        entry.pet = try petStore.ensurePet()
        return entry
    }

    // MARK: - Update / delete

    func updateDiary(_ entry: LogEntry, performedAt: Date, note: String?) throws {
        entry.performedAt = performedAt
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = (trimmed?.isEmpty == false) ? trimmed : nil
        try context.save()
    }

    func updateActivity(_ entry: LogEntry, type: ActivityType, performedAt: Date, note: String?, intervalDays: Int) throws {
        entry.activityType = type
        entry.performedAt = performedAt
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = (trimmed?.isEmpty == false) ? trimmed : nil
        entry.intervalDays = Int64(intervalDays)
        entry.nextDueAt = intervalDays > 0 ? calendar.date(byAdding: .day, value: intervalDays, to: performedAt) : nil
        try context.save()
    }

    func delete(_ entry: LogEntry) throws {
        context.delete(entry)
        try context.save()
    }

    // MARK: - Queries (pet-scoped, newest first)

    private func fetch(_ predicate: NSPredicate, limit: Int? = nil) throws -> [LogEntry] {
        let request = LogEntry.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        if let limit { request.fetchLimit = limit }
        return try context.fetch(request)
    }

    /// Every log entry for the current pet.
    func allEntries() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@", pet))
    }

    /// Diary entries = occurrences with no definition reference.
    func diaryEntries() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND activityType == nil AND medication == nil", pet))
    }

    /// Activity logs = occurrences tied to an ActivityType.
    func activityLogs() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND activityType != nil", pet))
    }

    func logs(of type: ActivityType) throws -> [LogEntry] {
        try fetch(NSPredicate(format: "activityType == %@", type))
    }

    func latestLog(of type: ActivityType) throws -> LogEntry? {
        try fetch(NSPredicate(format: "activityType == %@", type), limit: 1).first
    }

    func doses(for medication: Medication) throws -> [LogEntry] {
        try fetch(NSPredicate(format: "medication == %@", medication))
    }

    func lastDose(for medication: Medication) throws -> Date? {
        try fetch(NSPredicate(format: "medication == %@", medication), limit: 1).first?.performedAt
    }

    func doseCount(for medication: Medication) throws -> Int {
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "medication == %@", medication)
        return try context.count(for: request)
    }

    // MARK: - Photos

    @discardableResult
    func addPhoto(to entry: LogEntry, imageData: Data, caption: String? = nil, createdAt: Date = Date()) throws -> Photo {
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.imageData = imageData
        photo.caption = caption
        photo.createdAt = createdAt
        photo.pet = try petStore.ensurePet()
        photo.logEntry = entry
        try context.save()
        return photo
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }
}
