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

    init(context: NSManagedObjectContext, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
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

    func cancel() { clear() }

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

    private func writeEntry(for session: WalkSession, endedAt: Date?) throws -> LogEntry {
        let petStore = PetStore(context: context, defaults: defaults)
        if let typeID = session.activityTypeID {
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

    private func clear() { defaults.removeObject(forKey: Self.key) }
}
