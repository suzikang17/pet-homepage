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
            doseLogStore: DoseLogStore(context: context),
            vaccinationStore: VaccinationStore(context: context, petStore: petStore),
            vetVisitStore: VetVisitStore(context: context, petStore: petStore),
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

    func testEndpointAndTokenDefaultEmptyAndPersist() {
        let settings = UserDefaultsMirrorSettings(
            defaults: UserDefaults(suiteName: "endpoint-check-\(UUID().uuidString)")!
        )
        XCTAssertEqual(settings.mirrorEndpoint, "")
        XCTAssertEqual(settings.mirrorToken, "")
        settings.mirrorEndpoint = "https://dep.convex.site/mirror/push"
        settings.mirrorToken = "tok-xyz"
        XCTAssertEqual(settings.mirrorEndpoint, "https://dep.convex.site/mirror/push")
        XCTAssertEqual(settings.mirrorToken, "tok-xyz")
    }
}
