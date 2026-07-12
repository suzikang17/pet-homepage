// ios/PetHomepage/Notifications/WalkNotificationActions.swift
import CoreData
import Foundation
import UserNotifications

/// Actionable categories for walk detection: the "looks like a walk — log it?" prompt
/// (Start / Not now) and the "walk logged" auto-end receipt (Undo; a plain tap opens the app).
enum WalkNotificationAction {
    static let detectedCategoryID = "walkDetected"
    static let start = "walkStart"
    static let dismiss = "walkNotNow"

    static let endedCategoryID = "walkEnded"
    static let undo = "walkUndoEnd"

    /// UserDefaults flag set by "Not now": suppresses re-prompting until the next home exit
    /// (the detector clears it on exit). Lives in defaults because the action can arrive in a
    /// background launch where the detector's in-memory state is fresh.
    static let dismissedFlagKey = "walk.promptDismissedThisExcursion"

    /// The walk categories. Registered together with the routine ones by
    /// NotificationBootstrap.registerCategories — setNotificationCategories replaces the
    /// whole set, so exactly one call site composes all categories.
    static func categories() -> Set<UNNotificationCategory> {
        let start = UNNotificationAction(identifier: Self.start, title: "Start logging")
        let dismiss = UNNotificationAction(identifier: Self.dismiss, title: "Not now")
        let detected = UNNotificationCategory(identifier: detectedCategoryID,
                                              actions: [start, dismiss],
                                              intentIdentifiers: [])
        let undo = UNNotificationAction(identifier: Self.undo, title: "Undo")
        let ended = UNNotificationCategory(identifier: endedCategoryID,
                                           actions: [undo],
                                           intentIdentifiers: [])
        return [detected, ended]
    }
}

/// Request-identifier scheme for walk notifications. Walk IDs all start with "walk-" so the
/// shared notification responder can route them away from the routine handler.
///
/// - prompt: "walk-detected-a-<activityTypeUUID>-<exitEpoch>" or
///           "walk-detected-r-<routineTaskUUID>-<exitEpoch>"
/// - ended:  "walk-ended-<logEntryUUID>-<startEpoch>"
enum WalkRequestID {
    case detectedActivity(typeID: UUID, exitedAt: Date)
    case detectedRoutine(taskID: UUID, exitedAt: Date)
    case ended(entryID: UUID, startedAt: Date)

    var string: String {
        switch self {
        case let .detectedActivity(typeID, exitedAt):
            "walk-detected-a-\(typeID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))"
        case let .detectedRoutine(taskID, exitedAt):
            "walk-detected-r-\(taskID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))"
        case let .ended(entryID, startedAt):
            "walk-ended-\(entryID.uuidString)-\(Int(startedAt.timeIntervalSince1970))"
        }
    }

    static func parse(_ requestID: String) -> WalkRequestID? {
        let parts = requestID.split(separator: "-", omittingEmptySubsequences: false)
        // UUIDs themselves contain "-", so reassemble: prefix pieces, 5 UUID pieces, epoch.
        func uuid(from pieces: ArraySlice<Substring>) -> UUID? {
            UUID(uuidString: pieces.joined(separator: "-"))
        }
        if requestID.hasPrefix("walk-detected-a-") || requestID.hasPrefix("walk-detected-r-") {
            guard parts.count == 9, let epoch = Int(parts[8]),
                  let id = uuid(from: parts[3...7]) else { return nil }
            let date = Date(timeIntervalSince1970: TimeInterval(epoch))
            return parts[2] == "a" ? .detectedActivity(typeID: id, exitedAt: date)
                                   : .detectedRoutine(taskID: id, exitedAt: date)
        }
        if requestID.hasPrefix("walk-ended-") {
            guard parts.count == 8, let epoch = Int(parts[7]),
                  let id = uuid(from: parts[2...6]) else { return nil }
            return .ended(entryID: id, startedAt: Date(timeIntervalSince1970: TimeInterval(epoch)))
        }
        return nil
    }
}

/// Applies walk notification actions. Pure string-keyed logic, mirroring RoutineActionHandler:
/// the responder shim extracts (actionIdentifier, requestID) and calls this.
final class WalkActionHandler {
    private let sessions: WalkSessionStore
    private let context: NSManagedObjectContext
    private let defaults: UserDefaults
    private let now: () -> Date

    init(sessions: WalkSessionStore, context: NSManagedObjectContext,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.context = context
        self.defaults = defaults
        self.now = now
    }

    func handle(actionID: String, requestID: String) {
        guard let parsed = WalkRequestID.parse(requestID) else { return }
        switch (actionID, parsed) {
        case let (WalkNotificationAction.start, .detectedActivity(typeID, exitedAt)):
            guard sessions.active == nil else { return }
            _ = try? sessions.startActivity(typeID: typeID, startedAt: exitedAt, source: .detected)
        case let (WalkNotificationAction.start, .detectedRoutine(taskID, exitedAt)):
            guard sessions.active == nil else { return }
            _ = try? sessions.startRoutine(taskID: taskID, startedAt: exitedAt, source: .detected)
        case (WalkNotificationAction.dismiss, .detectedActivity),
             (WalkNotificationAction.dismiss, .detectedRoutine):
            defaults.set(true, forKey: WalkNotificationAction.dismissedFlagKey)
        case let (WalkNotificationAction.undo, .ended(entryID, startedAt)):
            undoEnd(entryID: entryID, startedAt: startedAt)
        default:
            break // plain tap opens the app
        }
    }

    /// Deletes the auto-ended entry and re-opens the session with its original start, so an
    /// accidental geofence end (e.g. walked past the house) can resume seamlessly.
    private func undoEnd(entryID: UUID, startedAt: Date) {
        guard sessions.active == nil else { return }
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? context.fetch(request).first else { return }

        // Capture the session reference before deleting the entry.
        let typeID = entry.activityType?.id
        var taskID: UUID?
        if entry.kind == .routine, let lineage = entry.routineLineageID {
            let taskRequest = RoutineTask.fetchRequest()
            taskRequest.predicate = NSPredicate(format: "lineageID == %@ AND effectiveUntil == nil",
                                                lineage as CVarArg)
            taskRequest.fetchLimit = 1
            taskID = (try? context.fetch(taskRequest).first)?.id
        }

        context.delete(entry)
        try? context.save()

        if let typeID {
            _ = try? sessions.startActivity(typeID: typeID, startedAt: startedAt, source: .detected)
        } else if let taskID {
            _ = try? sessions.startRoutine(taskID: taskID, startedAt: startedAt, source: .detected)
        }
    }
}
