// ios/PetHomepage/Stores/DoseLogStore.swift
import CoreData

/// Records when a dose of a medication was given and computes "last given".
final class DoseLogStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func logDose(for medication: Medication, at date: Date = Date(), note: String? = nil) throws -> DoseLog {
        let log = DoseLog(context: context)
        log.id = UUID()
        log.givenAt = date
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        log.note = (trimmed?.isEmpty == false) ? trimmed : nil
        log.medication = medication
        try context.save()
        return log
    }

    /// The most-recent `givenAt` for this medication, or nil if never given.
    func lastGiven(for medication: Medication) throws -> Date? {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(format: "medication == %@", medication)
        request.sortDescriptors = [NSSortDescriptor(key: "givenAt", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.givenAt
    }

    func doseCount(for medication: Medication) throws -> Int {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(format: "medication == %@", medication)
        return try context.count(for: request)
    }

    /// All logged doses for a medication, most-recent first.
    func logs(for medication: Medication) throws -> [DoseLog] {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(format: "medication == %@", medication)
        request.sortDescriptors = [NSSortDescriptor(key: "givenAt", ascending: false)]
        return try context.fetch(request)
    }

    func delete(_ log: DoseLog) throws {
        context.delete(log)
        try context.save()
    }
}
