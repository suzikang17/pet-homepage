// ios/PetHomepageTests/MirrorCoordinatorTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class MirrorCoordinatorTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func makeBuilder() -> SnapshotBuilder {
        let petStore = PetStore(context: context)
        return SnapshotBuilder(
            petStore: petStore,
            medicationStore: MedicationStore(context: context, petStore: petStore),
            recommendationStore: VetRecommendationStore(context: context),
            healthMarkerStore: HealthMarkerStore(context: context, petStore: petStore),
            symptomEpisodeStore: SymptomEpisodeStore(context: context, petStore: petStore),
            symptomEntryStore: SymptomEntryStore(context: context),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testDisabledMirroringPushesNothing() async throws {
        try PetStore(context: context).createPet(name: "Sandy", species: "dog")
        let service = FakeMirrorService()
        let settings = InMemoryMirrorSettings(initiallyEnabled: false)
        let coordinator = MirrorCoordinator(builder: makeBuilder(), service: service, settings: settings)

        let didPush = try await coordinator.syncIfEnabled()

        XCTAssertFalse(didPush)
        XCTAssertEqual(service.callCount, 0)
        XCTAssertTrue(service.pushedSnapshots.isEmpty)
    }

    func testEnabledMirroringPushesExactlyOneExpectedSnapshot() async throws {
        try PetStore(context: context).createPet(name: "Sandy", species: "dog")
        let service = FakeMirrorService()
        let settings = InMemoryMirrorSettings(initiallyEnabled: true)
        let coordinator = MirrorCoordinator(builder: makeBuilder(), service: service, settings: settings)

        let didPush = try await coordinator.syncIfEnabled()

        XCTAssertTrue(didPush)
        XCTAssertEqual(service.callCount, 1)
        XCTAssertEqual(service.pushedSnapshots.count, 1)
        XCTAssertEqual(service.pushedSnapshots.first?.pet.name, "Sandy")
        XCTAssertEqual(service.pushedSnapshots.first?.generatedAt,
                       Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testDefaultSettingsAreOptOut() {
        let settings = UserDefaultsMirrorSettings(
            defaults: UserDefaults(suiteName: "default-check-\(UUID().uuidString)")!
        )
        XCTAssertFalse(settings.isMirroringEnabled)
    }

    func testSettingPersistsThroughProtocol() {
        let settings = InMemoryMirrorSettings(initiallyEnabled: false)
        settings.isMirroringEnabled = true
        XCTAssertTrue(settings.isMirroringEnabled)
    }

    func testEndpointDefaultsEmptyAndPersistsInUserDefaults() {
        // mirrorEndpoint is stored in UserDefaults — accessible in unsigned test builds.
        let settings = UserDefaultsMirrorSettings(
            defaults: UserDefaults(suiteName: "endpoint-check-\(UUID().uuidString)")!
        )
        XCTAssertEqual(settings.mirrorEndpoint, "")
        settings.mirrorEndpoint = "https://dep.convex.site/mirror/push"
        XCTAssertEqual(settings.mirrorEndpoint, "https://dep.convex.site/mirror/push")
    }

    func testTokenDefaultsEmptyAndPersistsViaInMemorySettings() {
        // mirrorToken persistence in the production Keychain requires a signed binary.
        // InMemoryMirrorSettings is the test-double for this contract (isolated UserDefaults
        // suite) and exercises the same MirrorSettings protocol surface.
        let settings = InMemoryMirrorSettings(initiallyEnabled: false)
        XCTAssertEqual(settings.mirrorToken, "")
        settings.mirrorToken = "tok-xyz"
        XCTAssertEqual(settings.mirrorToken, "tok-xyz")
        settings.mirrorToken = ""
        XCTAssertEqual(settings.mirrorToken, "")
    }

    func testKeychainTokenRoundtripWhenSigned() throws {
        // SecItemAdd requires a signed host process. In unsigned xcodebuild test runs
        // the write silently fails, so we check the write status and skip if unavailable.
        let service = "pet.homepage.mirror.test.\(UUID().uuidString)"
        let account = "mirrorToken"
        KeychainHelper.save("tok-keychain", service: service, account: account)
        let read = KeychainHelper.read(service: service, account: account)
        if read == nil {
            // Keychain unavailable in this unsigned build environment — skip gracefully.
            throw XCTSkip("Keychain unavailable in unsigned test build (expected in CI/xcodebuild without signing)")
        }
        XCTAssertEqual(read, "tok-keychain")
        KeychainHelper.delete(service: service, account: account)
        XCTAssertNil(KeychainHelper.read(service: service, account: account))
    }
}
