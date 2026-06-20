// ios/PetHomepage/Mirror/MirrorSettings.swift
import Foundation

/// The opt-in privacy gate for the mirror. Injectable so views and the coordinator share
/// one source of truth and tests use an isolated UserDefaults suite.
protocol MirrorSettings: AnyObject {
    var isMirroringEnabled: Bool { get set }
    /// The Convex httpAction URL, e.g. https://<deployment>.convex.site/mirror/push. Blank = use the build default.
    var mirrorEndpoint: String { get set }
    /// The opaque bearer token minted in the dashboard. Blank until the user pastes one in.
    var mirrorToken: String { get set }
}

/// Production MirrorSettings backed by UserDefaults. Default is **false** — a copy of the
/// pet's health record only leaves iCloud after the owner explicitly opts in.
final class UserDefaultsMirrorSettings: MirrorSettings {
    private enum Key {
        static let isMirroringEnabled = "isMirroringEnabled"
        static let mirrorEndpoint = "mirrorEndpoint"
        static let mirrorToken = "mirrorToken"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMirroringEnabled: Bool {
        // `bool(forKey:)` returns false for an unset key — exactly the opt-out default we want.
        get { defaults.bool(forKey: Key.isMirroringEnabled) }
        set { defaults.set(newValue, forKey: Key.isMirroringEnabled) }
    }

    var mirrorEndpoint: String {
        get { defaults.string(forKey: Key.mirrorEndpoint) ?? "" }
        set { defaults.set(newValue, forKey: Key.mirrorEndpoint) }
    }

    var mirrorToken: String {
        get { defaults.string(forKey: Key.mirrorToken) ?? "" }
        set { defaults.set(newValue, forKey: Key.mirrorToken) }
    }
}
