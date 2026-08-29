// ios/PetHomepage/Stores/PhotoPool.swift
import CoreData
import Foundation

/// What a caller wants the photos of.
enum PhotoSubject {
    /// A user-defined activity type — one clean pool keyed on the relationship.
    case activityType(ActivityType)
    /// A routine slot. When the task is a walk this also unions the Walk activity type's
    /// logs, because detected walks land there instead of on the lineage.
    case routineTask(RoutineTask)
}

/// Resolves "every photo of X", read-side only.
///
/// This exists as a type rather than a helper on ActivityType because of one asymmetry: a walk
/// checked off in Schedule writes `kind = .routine` with a `routineLineageID` and no
/// `activityType`, while an auto-detected walk writes `kind = .activity` with `activityType`
/// set. Unifying those at write time is possible without a schema change, but it would fold
/// routine walks into `LogStore.latestLog(of:)` and shift the Walk type's due computation.
/// This codebase has been bitten by due-date drift before, so the union happens here on read
/// and nothing about due dates moves.
struct PhotoPool {
    private let context: NSManagedObjectContext
    private let home: HomeLocationStore

    init(context: NSManagedObjectContext, home: HomeLocationStore = HomeLocationStore()) {
        self.context = context
        self.home = home
    }

    /// Photos for `subject`, newest first. Empty rather than throwing when nothing matches.
    func photos(for subject: PhotoSubject) throws -> [Photo] {
        let entries = try entries(for: subject)
        guard !entries.isEmpty else { return [] }
        let request = Photo.fetchRequest()
        request.predicate = NSPredicate(format: "logEntry IN %@", entries)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    private func entries(for subject: PhotoSubject) throws -> [LogEntry] {
        let request = LogEntry.fetchRequest()
        switch subject {
        case .activityType(let type):
            request.predicate = NSPredicate(format: "activityType == %@", type)
        case .routineTask(let task):
            var predicates = [
                NSPredicate(format: "routineLineageID == %@", task.lineageID as CVarArg)
            ]
            if task.isWalk, let walkType = try walkActivityType(for: task.pet) {
                predicates.append(NSPredicate(format: "activityType == %@", walkType))
            }
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        }
        return try context.fetch(request)
    }

    /// The type detected walks log against. Mirrors `WalkActivityResolver.resolve` — the user's
    /// explicit pick first, then a walk-named type — so both agree on which type is "the walk
    /// one". It deliberately does not create a type the way the resolver does: this is a read
    /// path, and a pool query must never have a side effect.
    private func walkActivityType(for pet: Pet?) throws -> ActivityType? {
        guard let pet else { return nil }
        let request = ActivityType.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        let types = try context.fetch(request)
        if let chosen = home.defaultActivityTypeID,
           let match = types.first(where: { $0.id == chosen }) {
            return match
        }
        return types.first { $0.name.localizedCaseInsensitiveContains("walk") }
    }
}
