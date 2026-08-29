// ios/PetHomepage/Walk/WalkDetector.swift
import CoreData
import CoreLocation
import CoreMotion
import Foundation
import UIKit
import UserNotifications

/// The impure shell around WalkDetectorState: owns the home geofence (CLLocationManager
/// region monitoring) and the motion feed (CMMotionActivityManager), translates callbacks
/// into reducer events, and executes the effects (prompt notification / silent auto-end).
/// All decision logic lives in WalkDetectorState; this file should stay boring.
final class WalkDetector: NSObject {
    private static let regionID = "walk.home"
    /// The last home-exit time, persisted so the return-home wake can evaluate the excursion
    /// retroactively even when the process died in between (the in-memory reducer state does).
    static let lastExitKey = "walk.lastHomeExit"

    private let context: NSManagedObjectContext
    private let sessions: WalkSessionStore
    private let home: HomeLocationStore
    private let tuning: WalkDetectionTuning
    private let defaults: UserDefaults
    private let calendar: Calendar

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var state = WalkDetectorState.initial
    private var motionActive = false
    /// Computed once per excursion, at the home exit: did we leave near a scheduled slot or
    /// a learned habit time? Feeds the reducer's fast-confirm threshold on every sample.
    private var nearExpectedWalkThisExcursion = false

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
        super.init()
        locationManager.delegate = self
        // Settings screens post this when home/rule/type change; re-arm accordingly.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: .walkSettingsChanged, object: nil)
    }

    @objc private func settingsChanged() { refreshMonitoring() }

    /// (Re)arms the home geofence. Call at launch and whenever settings change. Monitoring
    /// requires Always authorization and a configured home; otherwise any existing region is
    /// removed (manual logging is never affected).
    func refreshMonitoring() {
        let monitored = locationManager.monitoredRegions.filter { $0.identifier == Self.regionID }
        guard home.isConfigured,
              locationManager.authorizationStatus == .authorizedAlways,
              let coordinate = home.homeCoordinate else {
            monitored.forEach { locationManager.stopMonitoring(for: $0) }
            stopMotion()
            return
        }
        monitored.forEach { locationManager.stopMonitoring(for: $0) }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                           longitude: coordinate.longitude),
            radius: tuning.homeRadiusMeters,
            identifier: Self.regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    // MARK: - Event plumbing

    private func dispatch(_ event: WalkDetectorEvent) {
        // "Not now" arrives via the notification handler (possibly in another launch);
        // surface it to the reducer before the triggering event.
        if defaults.bool(forKey: WalkNotificationAction.dismissedFlagKey) {
            defaults.removeObject(forKey: WalkNotificationAction.dismissedFlagKey)
            _ = state.apply(.promptDismissed, rule: home.promptRule,
                            hasActiveSession: sessions.active != nil,
                            isNearScheduledSlot: false, tuning: tuning)
        }
        let nearSlot = (try? WalkSlotFinder.openWalkSlot(
            near: Date(), withinMinutes: tuning.scheduledPromptWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)) != nil
        let effect = state.apply(event, rule: home.promptRule,
                                 hasActiveSession: sessions.active != nil,
                                 isNearScheduledSlot: nearSlot,
                                 isNearExpectedWalk: nearExpectedWalkThisExcursion,
                                 tuning: tuning)
        execute(effect)
    }

    private func execute(_ effect: WalkDetectorEffect) {
        switch effect {
        case let .promptStart(exitedAt):
            stopMotion()
            startDetectedWalk(exitedAt: exitedAt)
        case let .endSession(at):
            stopMotion()
            autoEnd(at: at)
        case .none:
            break
        }
    }

    // MARK: - Effects

    /// A walk was detected. With auto-log on (the default) it starts logging silently — against
    /// a near scheduled slot if one's open, else the resolved activity type — with a reversible
    /// "started" notice. With auto-log off, it posts the "log it?" prompt instead.
    private func startDetectedWalk(exitedAt: Date) {
        guard sessions.active == nil else { return }

        // Attach to an open routine walk slot when one is near; else resolve an activity type.
        let slotTask = try? WalkSlotFinder.openWalkSlot(
            near: exitedAt, withinMinutes: tuning.slotAttachWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)
        let resolvedTypeID = slotTask == nil
            ? WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
            : nil

        switch WalkStartDecision.mode(matchingSlotTaskID: slotTask?.id,
                                      resolvedTypeID: resolvedTypeID, autoLog: home.autoLog) {
        case let .silentRoutine(taskID):
            autoStart(taskID: taskID, name: slotTask?.name ?? "walk", exitedAt: exitedAt)
        case let .silentActivity(typeID):
            autoStartActivity(typeID: typeID, exitedAt: exitedAt)
        case .prompt:
            postPrompt(slotTask: slotTask, resolvedTypeID: resolvedTypeID, exitedAt: exitedAt)
        }
    }

    /// The "Out for a walk? — log it?" notification (auto-log off, or a manual fallback).
    private func postPrompt(slotTask: RoutineTask?, resolvedTypeID: UUID?, exitedAt: Date) {
        let requestID: WalkRequestID
        if let slotTask {
            requestID = .detectedRoutine(taskID: slotTask.id, exitedAt: exitedAt)
        } else if let typeID = resolvedTypeID {
            requestID = .detectedActivity(typeID: typeID, exitedAt: exitedAt)
        } else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Out for a walk?"
        content.body = "Looks like a walk with \(currentPetName()) — log it?"
        content.categoryIdentifier = WalkNotificationAction.detectedCategoryID
        content.sound = nil
        let request = UNNotificationRequest(identifier: requestID.string, content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Silently starts logging a matched scheduled walk (backdated to the home exit), shows
    /// the lock-screen timer, and posts a reversible "started" notice.
    private func autoStart(taskID: UUID, name: String, exitedAt: Date) {
        guard (try? sessions.startRoutine(taskID: taskID, startedAt: exitedAt,
                                          source: .detected)) != nil else { return }
        let petName = currentPetName()
        WalkLiveActivityController.sync(active: sessions.active, petName: petName)

        let content = UNMutableNotificationContent()
        content.title = "Walk started"
        content.body = "Logging \(name) for \(petName). Not a walk? Tap to cancel."
        content.categoryIdentifier = WalkNotificationAction.autoStartedCategoryID
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: WalkRequestID.autoStarted(taskID: taskID).string,
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Silently starts logging an off-schedule walk against a resolved activity type (backdated
    /// to the home exit), with the lock-screen timer and a reversible "started" notice.
    private func autoStartActivity(typeID: UUID, exitedAt: Date) {
        guard (try? sessions.startActivity(typeID: typeID, startedAt: exitedAt,
                                           source: .detected)) != nil else { return }
        let petName = currentPetName()
        WalkLiveActivityController.sync(active: sessions.active, petName: petName)

        let content = UNMutableNotificationContent()
        content.title = "Walk started"
        content.body = "Logging a walk with \(petName). Not a walk? Tap to cancel."
        content.categoryIdentifier = WalkNotificationAction.autoStartedCategoryID
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: WalkRequestID.autoStartedActivity(typeID: typeID).string,
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func currentPetName() -> String {
        (try? PetStore(context: context, defaults: defaults).currentPet()?.name)
            .flatMap { $0 } ?? "your pet"
    }

    private func autoEnd(at endDate: Date) {
        guard let session = sessions.active,
              let entry = try? sessions.end(at: endDate) else { return }
        WalkLiveActivityController.sync(active: nil, petName: "")

        let content = UNMutableNotificationContent()
        let minutes = entry.durationMinutes ?? 0
        content.title = "Walk logged"
        content.body = "\(minutes) min — tap to edit, or undo."
        content.categoryIdentifier = WalkNotificationAction.endedCategoryID
        content.sound = nil
        let requestID = WalkRequestID.ended(entryID: entry.id, startedAt: session.startedAt)
        let request = UNNotificationRequest(identifier: requestID.string, content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Motion

    private func startMotion() {
        guard !motionActive, CMMotionActivityManager.isActivityAvailable(),
              home.promptRule != .off else { return }
        motionActive = true
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.dispatch(.walkingSample(at: activity.startDate, isWalking: activity.walking))
        }
    }

    private func stopMotion() {
        guard motionActive else { return }
        motionActive = false
        motionManager.stopActivityUpdates()
    }

    // MARK: - Retroactive detection

    /// The live path needs the app alive for `sustainedWalkSeconds` of motion samples — a
    /// geofence wake lasts seconds, so a walk begun while the app was suspended is invisible
    /// to it. This path runs on the return-home wake instead: the whole excursion is already
    /// in CoreMotion's history, so query it and log the walk after the fact.
    private func evaluateRetroWalk(exitedAt: Date, enteredAt: Date,
                                   hadActiveSession: Bool, promptDismissed: Bool) {
        let nearSlot = (try? WalkSlotFinder.openWalkSlot(
            near: exitedAt, withinMinutes: tuning.scheduledPromptWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)) != nil
            || (try? WalkSlotFinder.openWalkSlot(
                near: enteredAt, withinMinutes: tuning.scheduledPromptWindowMinutes,
                context: context, defaults: defaults, calendar: calendar)) != nil
        guard RetroWalkDecision.shouldEvaluate(
            exitedAt: exitedAt, enteredAt: enteredAt, hadActiveSession: hadActiveSession,
            promptDismissed: promptDismissed, rule: home.promptRule,
            isNearScheduledSlot: nearSlot, tuning: tuning),
            CMMotionActivityManager.isActivityAvailable() else { return }

        // The geofence wake is short; the history query is async — buy time to finish it.
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "walk.retro")
        motionManager.queryActivityStarting(from: exitedAt, to: enteredAt,
                                            to: .main) { [weak self] activities, _ in
            defer { if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) } }
            guard let self else { return }
            let samples = (activities ?? []).map {
                MotionSample(startDate: $0.startDate, isWalking: $0.walking)
            }
            guard RetroWalkClassifier.sustainedWalk(in: samples, from: exitedAt,
                                                    until: enteredAt,
                                                    tuning: self.tuning) else { return }
            self.logRetroWalk(exitedAt: exitedAt, enteredAt: enteredAt)
        }
    }

    private func logRetroWalk(exitedAt: Date, enteredAt: Date) {
        guard sessions.active == nil else { return }
        let slotTask = try? WalkSlotFinder.openWalkSlot(
            near: exitedAt, withinMinutes: tuning.slotAttachWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)
        let resolvedTypeID = slotTask == nil
            ? WalkActivityResolver.resolve(context: context, home: home, defaults: defaults)
            : nil

        // A live "Out for a walk?" prompt may still be sitting on the lock screen from this
        // excursion; its Start action would open a session for a walk that's over.
        removeDeliveredDetectedPrompts()

        if home.autoLog {
            guard let entry = try? sessions.logCompleted(
                activityTypeID: resolvedTypeID, routineTaskID: slotTask?.id,
                startedAt: exitedAt, endedAt: enteredAt, source: .detected) else { return }
            let minutes = entry.durationMinutes ?? 0
            let content = UNMutableNotificationContent()
            content.title = "Walk logged"
            content.body = "\(minutes) min with \(currentPetName()) while you were out — tap to edit, or undo."
            content.categoryIdentifier = WalkNotificationAction.endedCategoryID
            content.sound = nil
            let request = UNNotificationRequest(
                identifier: WalkRequestID.retroLogged(entryID: entry.id).string,
                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            let requestID: WalkRequestID
            if let slotTask {
                requestID = .retroRoutine(taskID: slotTask.id, exitedAt: exitedAt,
                                          enteredAt: enteredAt)
            } else if let typeID = resolvedTypeID {
                requestID = .retroActivity(typeID: typeID, exitedAt: exitedAt,
                                           enteredAt: enteredAt)
            } else {
                return
            }
            let minutes = Int(enteredAt.timeIntervalSince(exitedAt) / 60)
            let content = UNMutableNotificationContent()
            content.title = "Log that walk?"
            content.body = "Looks like \(currentPetName()) got a \(minutes) min walk — log it?"
            content.categoryIdentifier = WalkNotificationAction.retroDetectedCategoryID
            content.sound = nil
            let request = UNNotificationRequest(identifier: requestID.string, content: content,
                                                trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Clears any still-delivered live prompts from this excursion so a retro log/prompt
    /// can't coexist with a stale "Start logging" button.
    private func removeDeliveredDetectedPrompts() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let stale = delivered.map(\.request.identifier)
                .filter { $0.hasPrefix("walk-detected-") }
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }
}

extension WalkDetector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        let exitedAt = Date()
        defaults.removeObject(forKey: WalkNotificationAction.dismissedFlagKey)
        defaults.set(exitedAt, forKey: Self.lastExitKey)
        // Leaving near a scheduled slot or a learned habit time? Then this is probably the
        // walk, and the short confirmation threshold applies for the rest of the excursion.
        let nearSlot = (try? WalkSlotFinder.openWalkSlot(
            near: exitedAt, withinMinutes: tuning.scheduledPromptWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)) != nil
        nearExpectedWalkThisExcursion = nearSlot || WalkHabitLearner.isNear(
            exitedAt,
            learned: WalkHabitLearner.learnedTimes(context: context, home: home,
                                                   calendar: calendar, tuning: tuning),
            windowMinutes: tuning.habitPriorWindowMinutes, calendar: calendar)
        dispatch(.exitedHome(at: exitedAt))
        // Motion checks only matter for prompting; auto-end needs just the geofence.
        if home.promptRule != .off, sessions.active == nil { startMotion() }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        let enteredAt = Date()
        // Capture before dispatch: dispatch consumes the "Not now" flag, and the reducer
        // ends the live session — both inputs the retro decision needs as they were.
        let exitedAt = defaults.object(forKey: Self.lastExitKey) as? Date
        defaults.removeObject(forKey: Self.lastExitKey)
        let hadActiveSession = sessions.active != nil
        let promptDismissed = defaults.bool(forKey: WalkNotificationAction.dismissedFlagKey)
        dispatch(.enteredHome(at: enteredAt))
        nearExpectedWalkThisExcursion = false
        if let exitedAt {
            evaluateRetroWalk(exitedAt: exitedAt, enteredAt: enteredAt,
                              hadActiveSession: hadActiveSession,
                              promptDismissed: promptDismissed)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshMonitoring()
    }
}
