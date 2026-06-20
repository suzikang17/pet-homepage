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
        // DEFERRED (Task 7, Step 5): The extraction UI (RecordUploadView / RecordUploadViewModel)
        // is not yet wired here — no production code path creates a URLSessionExtractionService
        // with a `secret:` value, which means the x-extract-secret header never reaches
        // /api/extract in a real run. When the extraction tab/sheet is wired, construct:
        //
        //   let extractSecret = UserDefaults.standard.string(forKey: "extractSecret") ?? ""
        //   let extractionService = URLSessionExtractionService(
        //       config: ExtractionConfig(
        //           endpoint: URL(string: "https://<host>/api/extract")!,
        //           secret: extractSecret.isEmpty ? nil : extractSecret
        //       )
        //   )
        //
        // and inject it into RecordUploadView. Until then the build links correctly because
        // RecordUploadView is compiled (it takes an injected ExtractionService) but is simply
        // not presented from any tab.

        let documentSharing = DocumentSharing(
            documentStore: DocumentStore.iCloudDrive()
                ?? DocumentStore(baseURL: FileManager.default.temporaryDirectory)
        )
        let settingsViewModel = SettingsViewModel(
            settings: mirrorSettings,
            coordinator: mirrorCoordinator,
            documentSharing: documentSharing,
            documentNames: []
        )

        return TabView {
            PetProfileView(store: petStore, settings: settingsViewModel)
                .tabItem { Label("Profile", systemImage: "pawprint") }
            MedicationsListView(medicationStore: medicationStore,
                                doseLogStore: doseLogStore,
                                reminderScheduler: reminderScheduler)
                .tabItem { Label("Meds", systemImage: "pills") }
            VaccinationsListView(store: vaccinationStore,
                                 dueScheduler: dueScheduler)
                .tabItem { Label("Vaccines", systemImage: "syringe") }
            VetVisitsListView(store: vetVisitStore,
                              recommendationStore: recommendationStore,
                              dueScheduler: dueScheduler,
                              cadenceMonths: vetCadenceMonths)
                .tabItem { Label("Vet", systemImage: "stethoscope") }
            HealthTabView(healthMarkerStore: healthMarkerStore,
                          symptomEpisodeStore: symptomEpisodeStore,
                          symptomEntryStore: symptomEntryStore)
                .tabItem { Label("Health", systemImage: "heart.text.square") }
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
