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

        // Phase 5 — opt-in desktop mirror wiring. The endpoint is a deferred-backend
        // placeholder; nothing leaves iCloud unless the owner opts in (default off).
        let mirrorSettings = UserDefaultsMirrorSettings()
        let mirrorService = URLSessionMirrorService(
            config: MirrorConfig(endpoint: URL(string: "https://example.com/api/mirror")!)
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
            PetProfileView(store: petStore)
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
            SettingsView(model: settingsViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// The Health tab bundles markers and symptoms into a single tab via an inner picker,
/// keeping the bottom tab bar uncrowded.
private struct HealthTabView: View {
    let healthMarkerStore: HealthMarkerStore
    let symptomEpisodeStore: SymptomEpisodeStore
    let symptomEntryStore: SymptomEntryStore

    @State private var section: Section = .markers

    private enum Section: String, CaseIterable, Identifiable {
        case markers = "Markers"
        case symptoms = "Symptoms"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch section {
            case .markers:
                HealthMarkersView(store: healthMarkerStore)
            case .symptoms:
                SymptomsListView(episodeStore: symptomEpisodeStore,
                                 entryStore: symptomEntryStore)
            }
        }
    }
}
