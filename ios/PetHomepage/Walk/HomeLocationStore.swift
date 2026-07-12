// ios/PetHomepage/Walk/HomeLocationStore.swift
import Foundation

/// Walk-detection preferences: home coordinate, prompt rule, and the default activity type a
/// detected walk logs against. UserDefaults-backed and device-local (detection is per-phone).
struct HomeLocationStore {
    private static let latKey = "walk.homeLat"
    private static let lonKey = "walk.homeLon"
    private static let ruleKey = "walk.promptRule"
    private static let typeKey = "walk.defaultActivityTypeID"

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

    /// Detection can run only once a home location and a default walk type are chosen.
    var isConfigured: Bool { homeCoordinate != nil && defaultActivityTypeID != nil }
}
