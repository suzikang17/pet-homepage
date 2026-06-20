import Foundation
@testable import PetHomepage

/// A MirrorSettings backed by a per-test UserDefaults suite, so tests neither touch nor
/// leak into `.standard`. Mirrors how production UserDefaultsMirrorSettings behaves.
final class InMemoryMirrorSettings: MirrorSettings {
    private let defaults: UserDefaults
    private let suiteName: String

    init(initiallyEnabled: Bool = false) {
        suiteName = "MirrorSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        isMirroringEnabled = initiallyEnabled
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    var isMirroringEnabled: Bool {
        get { defaults.bool(forKey: "isMirroringEnabled") }
        set { defaults.set(newValue, forKey: "isMirroringEnabled") }
    }

    var mirrorEndpoint: String {
        get { defaults.string(forKey: "mirrorEndpoint") ?? "" }
        set { defaults.set(newValue, forKey: "mirrorEndpoint") }
    }

    var mirrorToken: String {
        get { defaults.string(forKey: "mirrorToken") ?? "" }
        set { defaults.set(newValue, forKey: "mirrorToken") }
    }
}
