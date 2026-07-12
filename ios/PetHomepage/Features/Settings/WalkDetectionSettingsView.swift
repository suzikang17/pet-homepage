// ios/PetHomepage/Features/Settings/WalkDetectionSettingsView.swift
import CoreLocation
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
                        Picker("Log as", selection: $defaultTypeID) {
                            Text("Choose an activity…").tag(UUID?.none)
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

                        Picker("Prompt me", selection: $promptRule) {
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
                        case .denied, .restricted:
                            Link("Open Settings to allow location",
                                 destination: URL(string: UIApplication.openSettingsURLString)!)
                                .font(Theme.body().weight(.semibold))
                                .foregroundStyle(Theme.primary)
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
