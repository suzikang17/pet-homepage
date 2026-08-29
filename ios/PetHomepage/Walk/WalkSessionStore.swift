// ios/PetHomepage/Walk/WalkSessionStore.swift
import CoreData
import Foundation

enum WalkSessionError: Error, Equatable { case sessionAlreadyActive, unknownReference }

/// Owns the one active walk session and is the only path from "session" to "LogEntry".
/// Manual UI, notification actions, and WalkDetector are all just callers.
final class WalkSessionStore {
    /// A session forgotten longer than this is saved open-ended and cleared.
    static let maxSessionAge: TimeInterval = 4 * 60 * 60
    private static let key = "walk.activeSession"

    private let context: NSManagedObjectContext
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let pending: PendingWalkPhotos

    init(context: NSManagedObjectContext, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init,
         pending: PendingWalkPhotos = PendingWalkPhotos()) {
        self.context = context
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.pending = pending
    }

    var active: WalkSession? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WalkSession.self, from: data)
    }

    @discardableResult
    func startActivity(typeID: UUID, startedAt: Date? = nil,
                       source: WalkSession.Source) throws -> WalkSession {
        try start(WalkSession(id: UUID(), petID: nil, activityTypeID: typeID, routineTaskID: nil,
                              startedAt: startedAt ?? now(), source: source))
    }

    @discardableResult
    func startRoutine(taskID: UUID, startedAt: Date? = nil,
                      source: WalkSession.Source) throws -> WalkSession {
        try start(WalkSession(id: UUID(), petID: nil, activityTypeID: nil, routineTaskID: taskID,
                              startedAt: startedAt ?? now(), source: source))
    }

    /// Ends the active session, writing the LogEntry through the normal stores. Returns nil
    /// when there is no active session (stale notification action, double tap).
    @discardableResult
    func end(at endDate: Date? = nil) throws -> LogEntry? {
        guard let session = active else { return nil }
        let end = max(endDate ?? now(), session.startedAt)
        let entry = try writeEntry(for: session, endedAt: end)
        clear()
        return entry
    }

    /// Parks a mid-walk capture until `writeEntry` has an entry to attach it to. A no-op with
    /// no active session, which makes a late shutter tap after End harmless.
    func attachPhoto(_ jpeg: Data) {
        guard let session = active else { return }
        try? pending.add(jpeg, sessionID: session.id)
    }

    /// How many photos are waiting on the active session — drives the banner's badge.
    var pendingPhotoCount: Int {
        guard let session = active else { return 0 }
        return pending.count(for: session.id)
    }

    func cancel() {
        if let session = active { pending.clear(sessionID: session.id) }
        clear()
    }

    /// A forgotten session (older than maxSessionAge) is saved open-ended so the walk isn't
    /// lost, and cleared so a new one can start. The caller decides whether to notify.
    @discardableResult
    func expireIfStale() throws -> LogEntry? {
        guard let session = active,
              now().timeIntervalSince(session.startedAt) > Self.maxSessionAge else { return nil }
        let entry = try writeEntry(for: session, endedAt: nil)
        clear()
        return entry
    }

    // MARK: - Private

    private func start(_ session: WalkSession) throws -> WalkSession {
        guard active == nil else { throw WalkSessionError.sessionAlreadyActive }
        let data = try JSONEncoder().encode(session)
        defaults.set(data, forKey: Self.key)
        return session
    }

    /// The single path from session to LogEntry, so draining the pending buffer here covers a
    /// normal `end()` and a stale `expireIfStale()` without a second code path.
    private func writeEntry(for session: WalkSession, endedAt: Date?) throws -> LogEntry {
        let entry = try writeEntryCore(for: session, endedAt: endedAt)
        let buffered = pending.photos(for: session.id)
        guard !buffered.isEmpty else { return entry }
        let logStore = LogStore(context: context,
                                petStore: PetStore(context: context, defaults: defaults))
        for jpeg in buffered {
            // A single failed photo must not lose the walk itself, which is already written.
            _ = try? logStore.addPhoto(to: entry, imageData: jpeg)
        }
        pending.clear(sessionID: session.id)
        return entry
    }

    private func writeEntryCore(for session: WalkSession, endedAt: Date?) throws -> LogEntry {
        let petStore = PetStore(context: context, defaults: defaults)
        if let typeID = session.activityTypeID {
            // Reconcile with the schedule at END time too: prompt-time attachment can miss
            // (slot outside the window when the walk began, spontaneous walk near a slot).
            // If an open walk-like slot sits near this walk, completing it IS the walk.
            if let endedAt,
               let slotTask = openWalkSlot(near: endedAt) ?? openWalkSlot(near: session.startedAt) {
                let store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
                return try store.checkOff(slotTask, on: endedAt, now: endedAt,
                                          startedAt: session.startedAt, endedAt: endedAt)
            }
            let request = ActivityType.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", typeID as CVarArg)
            request.fetchLimit = 1
            guard let type = try context.fetch(request).first else {
                throw WalkSessionError.unknownReference
            }
            let logStore = LogStore(context: context, petStore: petStore)
            return try logStore.logActivity(type: type, performedAt: session.startedAt,
                                            endedAt: endedAt, note: nil,
                                            intervalDays: Int(type.defaultIntervalDays))
        }
        if let taskID = session.routineTaskID {
            let request = RoutineTask.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            request.fetchLimit = 1
            guard let task = try context.fetch(request).first else {
                throw WalkSessionError.unknownReference
            }
            let store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
            let reference = endedAt ?? now()
            // Dedupe: if the slot was already checked off in-app, don't create a second
            // completion — stamp the span onto the existing one instead.
            if let existing = try store.completion(of: task, on: reference) {
                existing.performedAt = session.startedAt
                if let endedAt, endedAt >= session.startedAt { existing.endedAt = endedAt }
                try context.save()
                return existing
            }
            return try store.checkOff(task, on: reference, now: reference,
                                      startedAt: session.startedAt, endedAt: endedAt)
        }
        throw WalkSessionError.unknownReference
    }

    /// Human name of what the active session is tracking ("Evening walk", "Walk") — shown by
    /// the in-progress banner so it's obvious which slot/activity the walk will complete.
    func title(for session: WalkSession) -> String? {
        if let taskID = session.routineTaskID {
            let request = RoutineTask.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?.name
        }
        if let typeID = session.activityTypeID {
            let request = ActivityType.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", typeID as CVarArg)
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?.name
        }
        return nil
    }

    private func openWalkSlot(near date: Date) -> RoutineTask? {
        (try? WalkSlotFinder.openWalkSlot(
            near: date,
            withinMinutes: WalkDetectionTuning.default.slotAttachWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)) ?? nil
    }

    private func clear() { defaults.removeObject(forKey: Self.key) }
}
