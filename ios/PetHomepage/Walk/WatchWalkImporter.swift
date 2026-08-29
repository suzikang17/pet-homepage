// ios/PetHomepage/Walk/WatchWalkImporter.swift
import CoreData
import Foundation
import HealthKit
import UserNotifications

/// Imports Outdoor Walk workouts recorded on Apple Watch as pet walks — the watch-only
/// outing (phone left at home) that the geofence detector can never see. An HKObserverQuery
/// with background delivery wakes the app when a workout lands; each new walking workout is
/// deduped against what's already logged (WatchWalkImportDecision) and then written through
/// the same slot-reconciliation path as every other walk.
final class WatchWalkImporter {
    private static let anchorKey = "walk.watchImportAnchor"

    private let context: NSManagedObjectContext
    private let sessions: WalkSessionStore
    private let home: HomeLocationStore
    private let tuning: WalkDetectionTuning
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let healthStore = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    init(context: NSManagedObjectContext, sessions: WalkSessionStore,
         home: HomeLocationStore = HomeLocationStore(),
         tuning: WalkDetectionTuning = .default,
         defaults: UserDefaults = .standard,
         calendar: Calendar = .current) {
        self.context = context
        self.sessions = sessions
        self.home = home
        self.tuning = tuning
        self.defaults = defaults
        self.calendar = calendar
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: .walkSettingsChanged, object: nil)
    }

    @objc private func settingsChanged() { refresh() }

    /// Arms or disarms the workout observer to match the preference. Call at launch — the
    /// observer must be re-registered every launch for background delivery to keep waking us.
    func refresh() {
        guard home.importWatchWalks, HKHealthStore.isHealthDataAvailable() else {
            stop()
            return
        }
        start()
    }

    private func start() {
        guard observerQuery == nil else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) {
            [weak self] _, completion, _ in
            guard let self else { completion(); return }
            self.importNewWorkouts { completion() }
        }
        observerQuery = query
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
        // Catch up on anything recorded while import was armed but the app never woke.
        importNewWorkouts {}
    }

    private func stop() {
        if let observerQuery { healthStore.stop(observerQuery) }
        observerQuery = nil
        healthStore.disableAllBackgroundDelivery { _, _ in }
    }

    // MARK: - Import pipeline

    /// Anchored query: only workouts not seen before. The anchor persists across launches so
    /// each workout is considered exactly once, whichever wake happens to process it.
    private func importNewWorkouts(done: @escaping () -> Void) {
        let query = HKAnchoredObjectQuery(
            type: HKObjectType.workoutType(),
            predicate: HKQuery.predicateForWorkouts(with: .walking),
            anchor: loadAnchor(), limit: HKObjectQueryNoLimit) {
            [weak self] _, samples, _, newAnchor, _ in
            // viewContext work belongs on main; HK calls back on an arbitrary queue.
            DispatchQueue.main.async {
                defer { done() }
                guard let self else { return }
                self.saveAnchor(newAnchor)
                for workout in (samples as? [HKWorkout]) ?? [] {
                    self.importIfEligible(workout)
                }
            }
        }
        healthStore.execute(query)
    }

    private func importIfEligible(_ workout: HKWorkout) {
        guard WatchWalkImportDecision.shouldImport(
            workoutStart: workout.startDate, workoutEnd: workout.endDate,
            importSince: home.watchImportSince,
            existingWalks: loggedWalkSpans(around: workout),
            activeSessionStart: sessions.active?.startedAt,
            tuning: tuning) else { return }

        let slotTask = try? WalkSlotFinder.openWalkSlot(
            near: workout.startDate, withinMinutes: tuning.slotAttachWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)
        let resolvedTypeID = slotTask == nil
            ? WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
            : nil
        guard slotTask != nil || resolvedTypeID != nil,
              let entry = try? sessions.logCompleted(
                activityTypeID: resolvedTypeID, routineTaskID: slotTask?.id,
                startedAt: workout.startDate, endedAt: workout.endDate,
                source: .watch) else { return }

        let content = UNMutableNotificationContent()
        let minutes = entry.durationMinutes ?? 0
        content.title = "Walk logged from Apple Watch"
        content.body = "\(minutes) min — tap to edit, or undo."
        content.categoryIdentifier = WalkNotificationAction.endedCategoryID
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: WalkRequestID.retroLogged(entryID: entry.id).string,
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Spans of walks already logged near the workout, for the duplicate check. Only
    /// walk-ish entries count (WalkLogQuery) — a meal check-off minutes before the workout
    /// must not block the import.
    private func loggedWalkSpans(around workout: HKWorkout) -> [LoggedWalkSpan] {
        let tolerance = TimeInterval(tuning.watchImportOverlapToleranceMinutes * 60)
        // Reach back far enough to catch a span entry that started before the window.
        let fetchStart = workout.startDate.addingTimeInterval(-tolerance - 6 * 60 * 60)
        let fetchEnd = workout.endDate.addingTimeInterval(tolerance)
        return WalkLogQuery.walkEntries(from: fetchStart, to: fetchEnd,
                                        context: context, home: home)
            .map { LoggedWalkSpan(start: $0.performedAt, end: $0.endedAt) }
    }

    // MARK: - Anchor persistence

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor,
                                                           requiringSecureCoding: true)
        else { return }
        defaults.set(data, forKey: Self.anchorKey)
    }
}
