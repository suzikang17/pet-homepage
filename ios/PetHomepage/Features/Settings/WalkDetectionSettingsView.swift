// ios/PetHomepage/Features/Settings/WalkDetectionSettingsView.swift
import CoreLocation
import HealthKit
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when any walk-detection preference changes so WalkDetector re-arms.
    static let walkSettingsChanged = Notification.Name("walkSettingsChanged")
}

/// Publishes the location authorization state and one-shot current location for the
/// settings/picker UI. UI-only; WalkDetector owns its own manager for monitoring.
final class LocationPermissionModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus
    @Published var lastLocation: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        status = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    func requestCurrentLocation() { manager.requestLocation() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.first?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // One-shot lookup failed (simulator, denied): the picker just stays on manual pin drop.
    }
}

/// Walk auto-detection preferences: home location, default walk type, prompt rule, and the
/// staged permission flow. Manual walk logging never depends on anything here.
struct WalkDetectionSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var permissions = LocationPermissionModel()

    private let home = HomeLocationStore()
    @State private var homeCoordinate: (latitude: Double, longitude: Double)?
    @State private var promptRule: WalkPromptRule = .anyWalk
    @State private var defaultTypeID: UUID?
    @State private var autoLog: Bool = true
    @State private var importWatchWalks: Bool = false
    @State private var learnedTimes: [LearnedWalkTime] = []
    @State private var timeSuggestions: [WalkSlotTimeSuggestion] = []
    @State private var showHomePicker = false
    @State private var showAlwaysExplainer = false

    private var activityTypes: [ActivityType] {
        let petStore = PetStore(context: context)
        return (try? ActivityStore(context: context, petStore: petStore).types()) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandCardTitle("Home location")
                        if let coordinate = homeCoordinate {
                            Label(String(format: "Set · %.4f, %.4f",
                                         coordinate.latitude, coordinate.longitude),
                                  systemImage: "house.fill")
                                .font(Theme.body()).foregroundStyle(Theme.ink)
                        } else {
                            Text("Required for detection — walks are noticed when you leave home and logged when you return.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        Button(homeCoordinate == nil ? "Set home location" : "Change home location") {
                            if permissions.status == .notDetermined {
                                permissions.requestWhenInUse()
                            }
                            showHomePicker = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }

                BrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandCardTitle("Detected walks")
                        // Optional: resolved automatically (walk-named type, or one created)
                        // when left alone — an unmade choice must never disarm detection.
                        Picker("Log as", selection: $defaultTypeID) {
                            Text("Automatic").tag(UUID?.none)
                            ForEach(activityTypes) { type in
                                Label(type.name, systemImage: type.iconName)
                                    .tag(UUID?.some(type.id))
                            }
                        }
                        .font(Theme.body()).tint(Theme.primary)
                        .onChange(of: defaultTypeID) { _, new in
                            home.defaultActivityTypeID = new
                            NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
                        }

                        Picker("Detect walks", selection: $promptRule) {
                            ForEach(WalkPromptRule.allCases, id: \.self) { rule in
                                Text(rule.displayName).tag(rule)
                            }
                        }
                        .font(Theme.body()).tint(Theme.primary)
                        .onChange(of: promptRule) { _, new in
                            home.promptRule = new
                            NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
                        }
                        Text("A detected walk near a scheduled walk slot checks that slot off with real start and end times.")
                            .font(.footnote).foregroundStyle(Theme.inkSoft)

                        Toggle("Auto-log without asking", isOn: $autoLog)
                            .font(Theme.body().weight(.semibold)).tint(Theme.primary)
                            .onChange(of: autoLog) { _, new in
                                home.autoLog = new
                                NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
                            }
                        Text("Log detected walks automatically with an undo notice, instead of asking first — scheduled and off-schedule walks alike. Turn off to be prompted before anything is logged.")
                            .font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                }

                BrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandCardTitle("Walk habits")
                        if learnedTimes.isEmpty {
                            Text("After a few logged walks, detection learns your usual times — leaving home near one confirms the walk in about 90 seconds instead of 4 minutes.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        } else {
                            Label(learnedSummary, systemImage: "clock.arrow.circlepath")
                                .font(Theme.body()).foregroundStyle(Theme.ink)
                            Text("Learned from your logged walks. Leaving home near these times confirms a walk fast.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        ForEach(timeSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("You usually walk around \(timeString(suggestion.suggestedHour, suggestion.suggestedMinute)), but “\(suggestion.slot.name)” is scheduled for \(timeString(suggestion.slot.hour, suggestion.slot.minute)).")
                                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                                Button("Set “\(suggestion.slot.name)” to \(timeString(suggestion.suggestedHour, suggestion.suggestedMinute))") {
                                    apply(suggestion)
                                }
                                .font(Theme.body().weight(.semibold))
                                .foregroundStyle(Theme.primary)
                            }
                        }
                    }
                }

                if HKHealthStore.isHealthDataAvailable() {
                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("Apple Watch")
                            Toggle("Import watch walks", isOn: $importWatchWalks)
                                .font(Theme.body().weight(.semibold)).tint(Theme.primary)
                                .onChange(of: importWatchWalks) { _, new in
                                    if new {
                                        enableWatchImport()
                                    } else {
                                        home.importWatchWalks = false
                                        NotificationCenter.default.post(
                                            name: .walkSettingsChanged, object: nil)
                                    }
                                }
                            Text("Outdoor Walk workouts recorded on your Apple Watch are logged as walks — even when your phone stays home. Only new workouts import, and anything already logged isn't duplicated. Needs permission to read workouts from Health.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }

                BrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandCardTitle("Permissions")
                        permissionStatus
                        switch permissions.status {
                        case .notDetermined:
                            Button("Enable auto-detection") { permissions.requestWhenInUse() }
                                .buttonStyle(PrimaryButtonStyle())
                        case .authorizedWhenInUse:
                            Button("Allow ending walks in the background") {
                                showAlwaysExplainer = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            // iOS shows the Always upgrade prompt only once per install — if
                            // it was answered (or never appeared), the button can't bring it
                            // back and only Settings can. Say so instead of looking broken.
                            Text("Nothing happened? iOS only offers that choice once. Open Settings → Privacy → Location Services → Pet Homepage and pick **Always**.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                            settingsLink
                        case .denied, .restricted:
                            settingsLink
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle("Walk detection")
        .onAppear {
            homeCoordinate = home.homeCoordinate
            promptRule = home.promptRule
            defaultTypeID = home.defaultActivityTypeID
            autoLog = home.autoLog
            importWatchWalks = home.importWatchWalks
            reloadHabits()
        }
        .sheet(isPresented: $showHomePicker) {
            HomeLocationPickerView(permissions: permissions,
                                   initial: homeCoordinate) { coordinate in
                home.homeCoordinate = coordinate
                homeCoordinate = coordinate
                NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
            }
        }
        .alert("One more step", isPresented: $showAlwaysExplainer) {
            Button("Allow Always") { permissions.requestAlways() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("“Always” access lets the walk end itself the moment you're home, even with the app closed. That's all it's used for.")
        }
    }

    // MARK: - Walk habits

    /// "Mornings ~7:05 AM · evenings ~5:32 PM" — hour < 12 decides the label.
    private var learnedSummary: String {
        learnedTimes
            .map { "\($0.hour < 12 ? "Mornings" : "Evenings") ~\(timeString($0.hour, $0.minute))" }
            .joined(separator: " · ")
    }

    private func timeString(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                                         of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func reloadHabits() {
        learnedTimes = WalkHabitLearner.learnedTimes(context: context, home: home)
        let slots = walkTasks.map {
            WalkSlotInfo(id: $0.id, name: $0.name, hour: Int($0.hour), minute: Int($0.minute))
        }
        timeSuggestions = WalkTimeSuggestion.suggestions(learned: learnedTimes, slots: slots)
    }

    private var walkTasks: [RoutineTask] {
        let petStore = PetStore(context: context)
        let store = RoutineStore(context: context, petStore: petStore)
        return ((try? store.currentTasks()) ?? []).filter(\.isWalk)
    }

    /// Versioned edit (past days keep the old time), then re-derive: a fresh suggestion set
    /// makes the applied one disappear, and the detector re-arms off the new slot time.
    private func apply(_ suggestion: WalkSlotTimeSuggestion) {
        guard let task = walkTasks.first(where: { $0.id == suggestion.slot.id }) else { return }
        let petStore = PetStore(context: context)
        let store = RoutineStore(context: context, petStore: petStore)
        _ = try? store.editTask(task, name: task.name, category: task.category,
                                iconName: task.iconName, hour: suggestion.suggestedHour,
                                minute: suggestion.suggestedMinute,
                                weekdayMask: task.weekdayMask)
        reloadHabits()
        NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
    }

    /// Asks Health for workout read access, then arms the importer. The import-since stamp
    /// is set once, on first enable, so re-enabling later can't pull in the gap's history.
    /// HealthKit hides read-authorization status, so the toggle reflects the preference —
    /// if the user denies in the Health sheet, imports silently find nothing.
    private func enableWatchImport() {
        let store = HKHealthStore()
        store.requestAuthorization(toShare: nil, read: [HKObjectType.workoutType()]) { _, _ in
            DispatchQueue.main.async {
                if home.watchImportSince == nil { home.watchImportSince = Date() }
                home.importWatchWalks = true
                NotificationCenter.default.post(name: .walkSettingsChanged, object: nil)
            }
        }
    }

    private var settingsLink: some View {
        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            .font(Theme.body().weight(.semibold))
            .foregroundStyle(Theme.primary)
    }

    private var permissionStatus: some View {
        let text: String
        switch permissions.status {
        case .authorizedAlways: text = "Always — detection fully enabled"
        case .authorizedWhenInUse: text = "While using — prompts work; background auto-end needs Always"
        case .denied, .restricted: text = "Denied — auto-detection is off (manual logging is unaffected)"
        case .notDetermined: text = "Not asked yet"
        @unknown default: text = "Unknown"
        }
        return Label(text, systemImage: "location")
            .font(.footnote).foregroundStyle(Theme.inkSoft)
    }
}
