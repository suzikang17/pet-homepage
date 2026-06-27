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
            symptomEntryStore: symptomEntryStore
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
            HealthTabView(healthMarkerStore: healthMarkerStore,
                          symptomEpisodeStore: symptomEpisodeStore,
                          symptomEntryStore: symptomEntryStore)
                .tabItem { Label("Health", systemImage: "heart.text.square") }
            CareTeamView(store: veterinarianStore)
                .tabItem { Label("Care Team", systemImage: "stethoscope") }
        }
        .tint(Theme.primary)
    }
}

/// The Health tab bundles markers and symptoms into a single tab via an inner picker,
/// keeping the bottom tab bar uncrowded.
private struct HealthTabView: View {
    let healthMarkerStore: HealthMarkerStore
    let symptomEpisodeStore: SymptomEpisodeStore
    let symptomEntryStore: SymptomEntryStore

    @State private var section: Section = .markers
    @State private var addMarker = false
    @State private var addEpisode = false

    private enum Section: String, CaseIterable, Identifiable {
        case markers = "Markers"
        case symptoms = "Symptoms"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HeroHeader(
                    title: "Health",
                    subtitle: section.rawValue,
                    systemImage: "heart.text.square.fill",
                    onAdd: { if section == .markers { addMarker = true } else { addEpisode = true } }
                )
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)

                switch section {
                case .markers:
                    HealthMarkersView(store: healthMarkerStore, showingAdd: $addMarker)
                case .symptoms:
                    SymptomsListView(episodeStore: symptomEpisodeStore,
                                     entryStore: symptomEntryStore,
                                     showingStart: $addEpisode)
                }
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
