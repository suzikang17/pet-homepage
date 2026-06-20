// ios/PetHomepage/Mirror/MirrorSettings.swift
import Foundation

/// The opt-in privacy gate for the mirror. Injectable so views and the coordinator share
/// one source of truth and tests use an isolated UserDefaults suite.
protocol MirrorSettings: AnyObject {
    var isMirroringEnabled: Bool { get set }
    /// The Convex httpAction URL, e.g. https://<deployment>.convex.site/mirror/push. Blank = use the build default.
    var mirrorEndpoint: String { get set }
    /// The opaque bearer token minted in the dashboard. Blank until the user pastes one in.
    /// In the production implementation this is stored in the device Keychain (not UserDefaults)
    /// because it is a write-capable bearer token for the user's Convex mirror.
    var mirrorToken: String { get set }
}

/// Production MirrorSettings.
/// - `isMirroringEnabled` and `mirrorEndpoint` are stored in UserDefaults (non-sensitive toggle + URL).
/// - `mirrorToken` is stored in the **Keychain** (`kSecClassGenericPassword`,
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) because it is a bearer credential
///   with write access to the user's Convex mirror. UserDefaults is unencrypted and is
///   included in unencrypted iTunes/iCloud backups, making it unsuitable for a secret.
final class UserDefaultsMirrorSettings: MirrorSettings {
    private enum DefaultsKey {
        static let isMirroringEnabled = "isMirroringEnabled"
        static let mirrorEndpoint = "mirrorEndpoint"
    }

    // Keychain coordinates for the bearer token.
    private enum KeychainKey {
        static let service = "pet.homepage.mirror"
        static let account = "mirrorToken"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMirroringEnabled: Bool {
        // `bool(forKey:)` returns false for an unset key — exactly the opt-out default we want.
        get { defaults.bool(forKey: DefaultsKey.isMirroringEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.isMirroringEnabled) }
    }

    var mirrorEndpoint: String {
        get { defaults.string(forKey: DefaultsKey.mirrorEndpoint) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.mirrorEndpoint) }
    }

    /// Stored in the Keychain, NOT UserDefaults. Writing an empty string removes the item.
    var mirrorToken: String {
        get { KeychainHelper.read(service: KeychainKey.service, account: KeychainKey.account) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(service: KeychainKey.service, account: KeychainKey.account)
            } else {
                KeychainHelper.save(newValue, service: KeychainKey.service, account: KeychainKey.account)
            }
        }
    }
}
