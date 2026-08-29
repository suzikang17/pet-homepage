// ios/PetHomepage/Walk/HomeLocationStore.swift
import Foundation

/// Walk-detection preferences: home coordinate, prompt rule, and the default activity type a
/// detected walk logs against. UserDefaults-backed and device-local (detection is per-phone).
struct HomeLocationStore {
    private static let latKey = "walk.homeLat"
    private static let lonKey = "walk.homeLon"
    private static let ruleKey = "walk.promptRule"
    private static let typeKey = "walk.defaultActivityTypeID"
    private static let autoLogKey = "walk.autoLog"
    private static let watchImportKey = "walk.importWatchWalks"
    private static let watchImportSinceKey = "walk.watchImportSince"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var homeCoordinate: (latitude: Double, longitude: Double)? {
        get {
            guard defaults.object(forKey: Self.latKey) != nil,
                  defaults.object(forKey: Self.lonKey) != nil else { return nil }
            return (defaults.double(forKey: Self.latKey), defaults.double(forKey: Self.lonKey))
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.latitude, forKey: Self.latKey)
                defaults.set(newValue.longitude, forKey: Self.lonKey)
            } else {
                defaults.removeObject(forKey: Self.latKey)
                defaults.removeObject(forKey: Self.lonKey)
            }
        }
    }

    var promptRule: WalkPromptRule {
        get {
            defaults.string(forKey: Self.ruleKey).flatMap(WalkPromptRule.init(rawValue:)) ?? .anyWalk
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.ruleKey) }
    }

    var defaultActivityTypeID: UUID? {
        get { defaults.string(forKey: Self.typeKey).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: Self.typeKey) }
    }

    /// Home is the only thing the user must choose — the activity a detected walk logs as is
    /// resolved automatically (see WalkActivityResolver), so a half-finished setup can't
    /// silently disarm detection.
    /// Auto-log detected walks silently (Live Activity + an undo notice) instead of asking
    /// first — for both scheduled-slot matches and off-schedule walks. With this off, every
    /// detection prompts. Defaults on; stored as an inverted "disabled" flag so an absent
    /// value reads as true.
    var autoLog: Bool {
        get { !defaults.bool(forKey: Self.autoLogKey + ".disabled") }
        nonmutating set { defaults.set(!newValue, forKey: Self.autoLogKey + ".disabled") }
    }

    /// Import Outdoor Walk workouts recorded on Apple Watch as pet walks. Off by default —
    /// it needs a Health read permission the user grants from Settings → Walk detection.
    var importWatchWalks: Bool {
        get { defaults.bool(forKey: Self.watchImportKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.watchImportKey) }
    }

    /// Set when watch import is first enabled: only workouts ending after this are imported,
    /// so flipping the toggle can't flood the log with months of workout history.
    var watchImportSince: Date? {
        get { defaults.object(forKey: Self.watchImportSinceKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.watchImportSinceKey) }
    }

    var isConfigured: Bool { homeCoordinate != nil }
}
