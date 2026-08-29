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

    static let autoStartedCategoryID = "walkAutoStarted"
    static let cancelStart = "walkCancelStart"

    /// Retroactive detection with auto-log off: the walk is already over, so the actions log
    /// a completed span rather than starting a session (same action IDs, different category
    /// so the titles fit the past tense).
    static let retroDetectedCategoryID = "walkRetroDetected"

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
        let cancel = UNNotificationAction(identifier: Self.cancelStart, title: "Cancel",
                                          options: [.destructive])
        let autoStarted = UNNotificationCategory(identifier: autoStartedCategoryID,
                                                 actions: [cancel],
                                                 intentIdentifiers: [])
        let logRetro = UNNotificationAction(identifier: Self.start, title: "Log walk")
        let dismissRetro = UNNotificationAction(identifier: Self.dismiss, title: "Not now")
        let retroDetected = UNNotificationCategory(identifier: retroDetectedCategoryID,
                                                   actions: [logRetro, dismissRetro],
                                                   intentIdentifiers: [])
        return [detected, ended, autoStarted, retroDetected]
    }
}

/// Request-identifier scheme for walk notifications. Walk IDs all start with "walk-" so the
/// shared notification responder can route them away from the routine handler.
///
/// - prompt: "walk-detected-a-<activityTypeUUID>-<exitEpoch>" or
///           "walk-detected-r-<routineTaskUUID>-<exitEpoch>"
/// - ended:  "walk-ended-<logEntryUUID>-<startEpoch>"
/// - retro prompt: "walk-retro-a-<activityTypeUUID>-<exitEpoch>-<enterEpoch>" or
///                 "walk-retro-r-<routineTaskUUID>-<exitEpoch>-<enterEpoch>"
/// - retro logged: "walk-retrologged-<logEntryUUID>"
enum WalkRequestID {
    case detectedActivity(typeID: UUID, exitedAt: Date)
    case detectedRoutine(taskID: UUID, exitedAt: Date)
    case ended(entryID: UUID, startedAt: Date)
    case autoStarted(taskID: UUID)
    case autoStartedActivity(typeID: UUID)
    /// Retro prompt (auto-log off): carries the full span because the walk is already over —
    /// "Log walk" writes a completed entry instead of starting a session.
    case retroActivity(typeID: UUID, exitedAt: Date, enteredAt: Date)
    case retroRoutine(taskID: UUID, exitedAt: Date, enteredAt: Date)
    /// Receipt for a walk logged after the fact (retro detection, watch import). Undo just
    /// deletes the entry — unlike `.ended`, there is no session to resume.
    case retroLogged(entryID: UUID)

    var string: String {
        switch self {
        case let .detectedActivity(typeID, exitedAt):
            "walk-detected-a-\(typeID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))"
        case let .detectedRoutine(taskID, exitedAt):
            "walk-detected-r-\(taskID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))"
        case let .ended(entryID, startedAt):
            "walk-ended-\(entryID.uuidString)-\(Int(startedAt.timeIntervalSince1970))"
        case let .autoStarted(taskID):
            "walk-autostarted-\(taskID.uuidString)"
        case let .autoStartedActivity(typeID):
            "walk-autostarted-a-\(typeID.uuidString)"
        case let .retroActivity(typeID, exitedAt, enteredAt):
            "walk-retro-a-\(typeID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))-\(Int(enteredAt.timeIntervalSince1970))"
        case let .retroRoutine(taskID, exitedAt, enteredAt):
            "walk-retro-r-\(taskID.uuidString)-\(Int(exitedAt.timeIntervalSince1970))-\(Int(enteredAt.timeIntervalSince1970))"
        case let .retroLogged(entryID):
            "walk-retrologged-\(entryID.uuidString)"
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
        if requestID.hasPrefix("walk-retro-a-") || requestID.hasPrefix("walk-retro-r-") {
            guard parts.count == 10, let exitEpoch = Int(parts[8]), let enterEpoch = Int(parts[9]),
                  let id = uuid(from: parts[3...7]) else { return nil }
            let exited = Date(timeIntervalSince1970: TimeInterval(exitEpoch))
            let entered = Date(timeIntervalSince1970: TimeInterval(enterEpoch))
            return parts[2] == "a" ? .retroActivity(typeID: id, exitedAt: exited, enteredAt: entered)
                                   : .retroRoutine(taskID: id, exitedAt: exited, enteredAt: entered)
        }
        if requestID.hasPrefix("walk-retrologged-") {
            guard parts.count == 7, let id = uuid(from: parts[2...6]) else { return nil }
            return .retroLogged(entryID: id)
        }
        // Activity variant ("-a-") must be checked before the routine one — it shares the
        // "walk-autostarted-" prefix but carries an extra segment.
        if requestID.hasPrefix("walk-autostarted-a-") {
            guard parts.count == 8, let id = uuid(from: parts[3...7]) else { return nil }
            return .autoStartedActivity(typeID: id)
        }
        if requestID.hasPrefix("walk-autostarted-") {
            guard parts.count == 7, let id = uuid(from: parts[2...6]) else { return nil }
            return .autoStarted(taskID: id)
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

    // @MainActor: mutates the main-queue viewContext from the delegate's arbitrary queue.
    @MainActor
    func handle(actionID: String, requestID: String) {
        guard let parsed = WalkRequestID.parse(requestID) else { return }
        defer {
            WalkLiveActivityController.sync(active: sessions.active, petName: currentPetName())
        }
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
        case let (WalkNotificationAction.start, .retroActivity(typeID, exitedAt, enteredAt)):
            _ = try? sessions.logCompleted(activityTypeID: typeID, routineTaskID: nil,
                                           startedAt: exitedAt, endedAt: enteredAt,
                                           source: .detected)
        case let (WalkNotificationAction.start, .retroRoutine(taskID, exitedAt, enteredAt)):
            _ = try? sessions.logCompleted(activityTypeID: nil, routineTaskID: taskID,
                                           startedAt: exitedAt, endedAt: enteredAt,
                                           source: .detected)
        case (WalkNotificationAction.dismiss, .retroActivity),
             (WalkNotificationAction.dismiss, .retroRoutine):
            break // the walk is over — declining just dismisses, nothing to suppress
        case let (WalkNotificationAction.undo, .retroLogged(entryID)):
            // Logged after the fact, so there's no session to resume — delete the entry.
            deleteEntry(entryID: entryID)
        case (WalkNotificationAction.cancelStart, .autoStarted),
             (WalkNotificationAction.cancelStart, .autoStartedActivity):
            // A false auto-start: discard the running session without logging.
            sessions.cancel()
        default:
            break // plain tap opens the app
        }
    }

    private func currentPetName() -> String {
        // try? flattens the throwing Optional return (SE-0230), so one binding suffices.
        if let pet = try? PetStore(context: context, defaults: defaults).currentPet() {
            return pet.name
        }
        return "Your pet"
    }

    private func deleteEntry(entryID: UUID) {
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? context.fetch(request).first else { return }
        context.delete(entry)
        try? context.save()
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
