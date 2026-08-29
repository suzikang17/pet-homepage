// ios/PetHomepage/Walk/WalkLogQuery.swift
import CoreData
import Foundation

/// Shared "which log entries are walks?" logic, used by watch-import dedupe and habit
/// learning. Activity entries qualify by walk-named (or default-picked) type; routine
/// entries by their current task's isWalk flag, resolved through the lineage.
enum WalkLogQuery {
    /// Walk entries whose start falls inside [from, to], oldest first.
    static func walkEntries(from: Date, to: Date,
                            context: NSManagedObjectContext,
                            home: HomeLocationStore = HomeLocationStore()) -> [LogEntry] {
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "performedAt >= %@ AND performedAt <= %@ AND kindRaw IN %@",
            from as CVarArg, to as CVarArg,
            [LogKind.activity.rawValue, LogKind.routine.rawValue])
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: true)]
        let entries = (try? context.fetch(request)) ?? []
        return entries.filter { isWalkEntry($0, context: context, home: home) }
    }

    static func isWalkEntry(_ entry: LogEntry, context: NSManagedObjectContext,
                            home: HomeLocationStore = HomeLocationStore()) -> Bool {
        switch entry.kind {
        case .activity:
            guard let type = entry.activityType else { return false }
            return type.id == home.defaultActivityTypeID
                || type.name.localizedCaseInsensitiveContains("walk")
        case .routine:
            guard let lineage = entry.routineLineageID else { return false }
            let request = RoutineTask.fetchRequest()
            request.predicate = NSPredicate(format: "lineageID == %@ AND effectiveUntil == nil",
                                            lineage as CVarArg)
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?.isWalk ?? false
        default:
            return false
        }
    }
}
