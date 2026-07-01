// ios/PetHomepageTests/SettingsViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class SettingsViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var baseURL: URL!
    private var documentStore: DocumentStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        documentStore = DocumentStore(baseURL: baseURL)
        try PetStore(context: context).createPet(name: "Sandy", species: "dog")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    private func makeCoordinator(service: MirrorService, settings: MirrorSettings) -> MirrorCoordinator {
        let petStore = PetStore(context: context)
        let builder = SnapshotBuilder(
            petStore: petStore,
            medicationStore: MedicationStore(context: context, petStore: petStore),
            vaccinationStore: VaccinationStore(context: context, petStore: petStore),
            vetVisitStore: VetVisitStore(context: context, petStore: petStore),
            recommendationStore: VetRecommendationStore(context: context),
            healthMarkerStore: HealthMarkerStore(context: context, petStore: petStore),
            symptomEpisodeStore: SymptomEpisodeStore(context: context, petStore: petStore),
            symptomEntryStore: SymptomEntryStore(context: context),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return MirrorCoordinator(builder: builder, service: service, settings: settings)
    }

    private func makeViewModel(settings: MirrorSettings,
                               service: MirrorService,
                               documentNames: [String]) -> SettingsViewModel {
        SettingsViewModel(
            settings: settings,
            coordinator: makeCoordinator(service: service, settings: settings),
            documentSharing: DocumentSharing(documentStore: documentStore),
            documentNames: documentNames
        )
    }

    func testTogglingMirroringWritesThroughToSettings() {
        let settings = InMemoryMirrorSettings(initiallyEnabled: false)
        let vm = makeViewModel(settings: settings, service: FakeMirrorService(), documentNames: [])

        XCTAssertFalse(vm.isMirroringEnabled)
        vm.isMirroringEnabled = true

        XCTAssertTrue(settings.isMirroringEnabled)
        XCTAssertTrue(vm.isMirroringEnabled)
    }

    func testLoadDocumentsListsOnlyExistingFiles() throws {
        try documentStore.save(Data("a".utf8), named: "labs.pdf")
        let settings = InMemoryMirrorSettings()
        let vm = makeViewModel(settings: settings, service: FakeMirrorService(),
                               documentNames: ["labs.pdf", "ghost.pdf"])

        vm.loadDocuments()

        XCTAssertEqual(vm.documentRows.count, 1)
        XCTAssertEqual(vm.documentRows.first?.reference.fileName, "labs.pdf")
    }

    func testShareURLForRowReturnsFileURL() throws {
        let saved = try documentStore.save(Data("a".utf8), named: "labs.pdf")
        let vm = makeViewModel(settings: InMemoryMirrorSettings(), service: FakeMirrorService(),
                               documentNames: ["labs.pdf"])
        vm.loadDocuments()

        let url = try vm.shareURL(for: vm.documentRows[0])

        XCTAssertEqual(url, saved)
    }

    func testSyncNowPushesWhenEnabled() async throws {
        let settings = InMemoryMirrorSettings(initiallyEnabled: true)
        let service = FakeMirrorService()
        let vm = makeViewModel(settings: settings, service: service, documentNames: [])

        let didPush = try await vm.syncNow()

        XCTAssertTrue(didPush)
        XCTAssertEqual(service.callCount, 1)
    }

    func testSyncNowDoesNothingWhenDisabled() async throws {
        let settings = InMemoryMirrorSettings(initiallyEnabled: false)
        let service = FakeMirrorService()
        let vm = makeViewModel(settings: settings, service: service, documentNames: [])

        let didPush = try await vm.syncNow()

        XCTAssertFalse(didPush)
        XCTAssertEqual(service.callCount, 0)
    }

    func testPrivacyNoteWarnsDataLeavesICloud() {
        let vm = makeViewModel(settings: InMemoryMirrorSettings(), service: FakeMirrorService(),
                               documentNames: [])
        XCTAssertTrue(vm.privacyNote.lowercased().contains("icloud"))
    }
}
