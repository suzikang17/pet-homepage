// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    /// v1 default vet-visit cadence: see the vet every 6 months.
    private let vetCadenceMonths = 6

    var body: some View {
        let petStore = PetStore(context: context)
        let medicationStore = MedicationStore(context: context, petStore: petStore)
        let doseLogStore = DoseLogStore(context: context)
        let vaccinationStore = VaccinationStore(context: context, petStore: petStore)
        let vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        let recommendationStore = VetRecommendationStore(context: context)
        let reminderScheduler = MedicationReminderScheduler(scheduler: UNNotificationScheduler())
        let dueScheduler = DueReminderScheduler(scheduler: UNNotificationScheduler())
        let healthMarkerStore = HealthMarkerStore(context: context, petStore: petStore)
        let symptomEpisodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
        let symptomEntryStore = SymptomEntryStore(context: context)
        let veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
        let diaryStore = DiaryStore(context: context, petStore: petStore)

        // Web integration bridge: build the mirror push client from the user-entered endpoint
        // + token (Settings). Blank endpoint falls back to the build-time Convex .site default.
        let mirrorSettings = UserDefaultsMirrorSettings()
        let defaultMirrorEndpoint = "https://your-deployment.convex.site/mirror/push"
        let mirrorEndpointString = mirrorSettings.mirrorEndpoint.isEmpty
            ? defaultMirrorEndpoint
            : mirrorSettings.mirrorEndpoint
        let mirrorEndpoint = URL(string: mirrorEndpointString)
            ?? URL(string: defaultMirrorEndpoint)!
        let mirrorService = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: mirrorEndpoint,
                token: mirrorSettings.mirrorToken.isEmpty ? nil : mirrorSettings.mirrorToken
            )
        )
        let snapshotBuilder = SnapshotBuilder(
            petStore: petStore,
            medicationStore: medicationStore,
            doseLogStore: doseLogStore,
            vaccinationStore: vaccinationStore,
            vetVisitStore: vetVisitStore,
            recommendationStore: recommendationStore,
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            symptomEntryStore: symptomEntryStore,
            veterinarianStore: veterinarianStore
        )
        let mirrorCoordinator = MirrorCoordinator(
            builder: snapshotBuilder,
            service: mirrorService,
            settings: mirrorSettings
        )
        // AI record extraction: the "Scan a record" sheet picks a PDF/photo → /api/extract
        // (Claude) → writes the parsed records. Endpoint + secret are configured in Settings
        // (UserDefaults); a blank endpoint just means the upload errors until it's set.
        let documentStore = DocumentStore.iCloudDrive()
            ?? DocumentStore(baseURL: FileManager.default.temporaryDirectory)
        let documentSharing = DocumentSharing(documentStore: documentStore)
        let ingestionService = RecordIngestionService(
            vaccinationStore: vaccinationStore,
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            documentStore: documentStore
        )
        let extractEndpoint = UserDefaults.standard.string(forKey: "extractEndpoint") ?? ""
        let extractSecret = UserDefaults.standard.string(forKey: "extractSecret") ?? ""
        let extractionService = URLSessionExtractionService(
            config: ExtractionConfig(
                endpoint: URL(string: extractEndpoint) ?? URL(string: "https://example.invalid/api/extract")!,
                secret: extractSecret.isEmpty ? nil : extractSecret
            )
        )
        let settingsViewModel = SettingsViewModel(
            settings: mirrorSettings,
            coordinator: mirrorCoordinator,
            documentSharing: documentSharing,
            documentNames: []
        )

        // The unified read stream + everything its rows need to open each record's editor.
        let timelineServices = TimelineServices(
            vaccinationStore: vaccinationStore,
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            doseLogStore: doseLogStore,
            veterinarianStore: veterinarianStore,
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            symptomEntryStore: symptomEntryStore,
            recommendationStore: recommendationStore,
            reminderScheduler: reminderScheduler,
            dueScheduler: dueScheduler,
            cadenceMonths: vetCadenceMonths
        )

        return TabView {
            PetProfileView(store: petStore, settings: settingsViewModel,
                           extractionService: extractionService, ingestionService: ingestionService,
                           timelineServices: timelineServices)
                .tabItem { Label("Home", systemImage: "house") }
            TimelineView(services: timelineServices)
                .tabItem { Label("Timeline", systemImage: "calendar") }
            DiaryView(store: diaryStore)
                .tabItem { Label("Diary", systemImage: "book") }
            CareTeamView(store: veterinarianStore)
                .tabItem { Label("Care Team", systemImage: "stethoscope") }
        }
        .tint(Theme.primary)
    }
}
