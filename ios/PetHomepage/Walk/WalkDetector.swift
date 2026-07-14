// ios/PetHomepage/Walk/WalkDetector.swift
import CoreData
import CoreLocation
import CoreMotion
import Foundation
import UserNotifications

/// The impure shell around WalkDetectorState: owns the home geofence (CLLocationManager
/// region monitoring) and the motion feed (CMMotionActivityManager), translates callbacks
/// into reducer events, and executes the effects (prompt notification / silent auto-end).
/// All decision logic lives in WalkDetectorState; this file should stay boring.
final class WalkDetector: NSObject {
    private static let regionID = "walk.home"

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
                                 isNearScheduledSlot: nearSlot, tuning: tuning)
        execute(effect)
    }

    private func execute(_ effect: WalkDetectorEffect) {
        switch effect {
        case let .promptStart(exitedAt):
            stopMotion()
            postStartPrompt(exitedAt: exitedAt)
        case let .endSession(at):
            stopMotion()
            autoEnd(at: at)
        case .none:
            break
        }
    }

    // MARK: - Effects

    private func postStartPrompt(exitedAt: Date) {
        // Attach to an open routine walk slot when one is near; else the default type.
        let slotTask = try? WalkSlotFinder.openWalkSlot(
            near: exitedAt, withinMinutes: tuning.slotAttachWindowMinutes,
            context: context, defaults: defaults, calendar: calendar)
        let requestID: WalkRequestID
        if let slotTask {
            requestID = .detectedRoutine(taskID: slotTask.id, exitedAt: exitedAt)
        } else if let typeID = WalkActivityResolver.resolve(context: context, home: home,
                                                            defaults: defaults) {
            requestID = .detectedActivity(typeID: typeID, exitedAt: exitedAt)
        } else {
            return
        }

        let content = UNMutableNotificationContent()
        let petName = (try? PetStore(context: context, defaults: defaults).currentPet()?.name)
            .flatMap { $0 } ?? "your pet"
        content.title = "Out for a walk?"
        content.body = "Looks like a walk with \(petName) — log it?"
        content.categoryIdentifier = WalkNotificationAction.detectedCategoryID
        content.sound = nil
        let request = UNNotificationRequest(identifier: requestID.string, content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
}

extension WalkDetector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        defaults.removeObject(forKey: WalkNotificationAction.dismissedFlagKey)
        dispatch(.exitedHome(at: Date()))
        // Motion checks only matter for prompting; auto-end needs just the geofence.
        if home.promptRule != .off, sessions.active == nil { startMotion() }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        dispatch(.enteredHome(at: Date()))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshMonitoring()
    }
}
