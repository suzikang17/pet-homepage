// ios/PetHomepage/App/ContentView.swift
import PhotosUI
import SwiftUI
import UIKit

/// A just-captured (or library-picked) photo, already downscaled — wrapped so it can drive a
/// `.sheet(item:)` for the review-and-tag flow.
private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

/// A record-editor handoff staged from the capture review sheet: which editor to open, with the
/// photo that should arrive pre-staged as a pending photo. Wrapped so it can drive
/// `.sheet(item:)` once the review sheet has fully dismissed.
private struct HandoffPresentation: Identifiable {
    let id = UUID()
    let kind: RecordHandoff
    let photo: Data
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(NotificationRouter.self) private var deeplinkRouter: NotificationRouter?

    /// v1 default vet-visit cadence: see the vet every 6 months.
    private let vetCadenceMonths = 6

    /// Home (tag 0) is the launch tab: it carries the cadence catalogue, so it answers "what
    /// does this pet need" on open. Tab *tags* are NotificationRouter's deep-link targets and
    /// must stay fixed — only the declaration order below controls display order.
    @State private var selectedTab = 0
    @State private var showCamera = false
    @State private var showLibraryFallback = false
    @State private var libraryItem: PhotosPickerItem?
    /// Staged during capture; promoted to `capturedPhoto` only after the camera cover has fully
    /// dismissed. Presenting the review sheet in the same transaction as the cover's dismissal
    /// is a known SwiftUI flake (the sheet can silently never appear).
    @State private var pendingPhoto: Data?
    @State private var capturedPhoto: CapturedPhoto?
    /// Staged the same way as `pendingPhoto`: a "Vaccine"/"Vet visit" chip in the review sheet
    /// dismisses that sheet and records the handoff here; once the review sheet's `onDismiss`
    /// fires, it's promoted to `activeHandoff` to present the prefilled editor. Presenting the
    /// editor sheet in the same transaction as the review sheet's dismissal is the same known
    /// SwiftUI flake as the camera cover above.
    @State private var pendingHandoff: HandoffPresentation?
    @State private var activeHandoff: HandoffPresentation?

    // One-time walk-detection intro; [Set up] chains into the settings sheet via the same
    // pending-flag/onDismiss pattern as the capture handoffs above.
    @AppStorage("walk.introShown") private var walkIntroShown = false
    @State private var showWalkIntro = false
    @State private var pendingWalkSetup = false
    @State private var showWalkSetupSheet = false
    /// Set by the camera's library shortcut; promoted to the picker on camera dismissal.
    @State private var pendingLibraryFromCamera = false
    /// Development scratchpad, opened by shaking the phone from any tab.
    @State private var showIdeas = false
    /// App-icon "Jot an idea" quick action; observed so cold and warm launches both open the
    /// sheet. `@State` keeps the shared reference participating in SwiftUI observation.
    @State private var quickActions = QuickActionRouter.shared
    /// True while the sheet was opened from the app icon — those ideas are stamped "App icon"
    /// rather than the current tab, which the user never saw.
    @State private var ideasFromQuickAction = false

    /// Opens the capture flow from the Timeline + menu: staged stub photo under
    /// `--uitest-stub-camera`, the camera when available, else the photo-library picker.
    private func startCapture() {
        if UITestSupport.stubCamera {
            if let jpeg = UITestSupport.stubPhotoJPEG() {
                capturedPhoto = CapturedPhoto(data: jpeg)
            }
            return
        }
        if CameraPicker.isAvailable {
            showCamera = true
        } else {
            showLibraryFallback = true
        }
    }

    /// Tab tags are load-bearing (`NotificationRouter` deep links) — this only reads them, to
    /// label an idea with where it was captured.
    private static func screenLabel(for tag: Int) -> String? {
        switch tag {
        case 0: return "Home"
        case 1: return "Timeline"
        case 3: return "Schedule"
        case 4: return "Care Team"
        default: return nil
        }
    }

    var body: some View {
        let petStore = PetStore(context: context)
        let medicationStore = MedicationStore(context: context, petStore: petStore)
        let recommendationStore = VetRecommendationStore(context: context)
        let reminderScheduler = MedicationReminderScheduler(scheduler: UNNotificationScheduler())
        let dueScheduler = DueReminderScheduler(scheduler: UNNotificationScheduler())
        let symptomEntryStore = SymptomEntryStore(context: context)
        let activityStore = ActivityStore(context: context, petStore: petStore)
        let routineStore = RoutineStore(context: context, petStore: petStore)
        let routineReminderScheduler = RoutineReminderScheduler(scheduler: UNNotificationScheduler())
        let veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
        let diaryStore = DiaryStore(context: context, petStore: petStore)
        let logStore = LogStore(context: context, petStore: petStore)
        let walkSessions = WalkSessionStore(context: context)

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
            recommendationStore: recommendationStore,
            symptomEntryStore: symptomEntryStore,
            veterinarianStore: veterinarianStore,
            logStore: logStore
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
            logStore: logStore,
            medicationStore: medicationStore,
            documentStore: documentStore
        )
        let extractEndpoint = UserDefaults.standard.string(forKey: "extractEndpoint") ?? ""
        let extractSecret = UserDefaults.standard.string(forKey: "extractSecret") ?? ""
        // Under `--uitest` with no endpoint configured, extraction is genuinely unusable — pass
        // nil so the "Scan a record" menu entry stays hidden (deterministic for UI tests).
        // Normal launches keep the existing always-on service (it just errors until configured).
        let extractionService: ExtractionService? = (UITestSupport.isUITest && extractEndpoint.isEmpty)
            ? nil
            : URLSessionExtractionService(
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
            medicationStore: medicationStore,
            veterinarianStore: veterinarianStore,
            diaryStore: diaryStore,
            symptomEntryStore: symptomEntryStore,
            recommendationStore: recommendationStore,
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: reminderScheduler,
            dueScheduler: dueScheduler,
            cadenceMonths: vetCadenceMonths,
            extractionService: extractionService,
            ingestionService: ingestionService
        )

        return TabView(selection: $selectedTab) {
            // Display order only — the .tag values are load-bearing: NotificationRouter.Tab maps
            // raw values to these tags, so reordering must never renumber them.
            PetProfileView(store: petStore, settings: settingsViewModel,
                           timelineServices: timelineServices)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            ScheduleView(store: routineStore, logStore: logStore,
                         reminderScheduler: routineReminderScheduler, petStore: petStore,
                         walkSessions: walkSessions, timelineServices: timelineServices)
                .tabItem { Label("Schedule", systemImage: "checklist") }
                .tag(3)
            TimelineView(services: timelineServices, onCapture: { startCapture() },
                         onImport: { showLibraryFallback = true })
                .tabItem { Label("Timeline", systemImage: "calendar") }
                .tag(1)
            CareTeamView(store: veterinarianStore)
                .tabItem { Label("Care Team", systemImage: "stethoscope") }
                .tag(4)
        }
        .tint(Theme.primary)
        .background(ShakeDetector { showIdeas = true })
        .sheet(isPresented: $showIdeas, onDismiss: { ideasFromQuickAction = false }) {
            NavigationStack {
                IdeaListView(store: FileIdeaStore.documents(),
                             screen: ideasFromQuickAction
                                 ? "App icon"
                                 : Self.screenLabel(for: selectedTab))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showIdeas = false }
                        }
                    }
            }
        }
        // App-icon quick action, warm path: the router flips while the UI is live. The cold
        // path (flag set before this view existed) is consumed in .task below.
        .onChange(of: quickActions.pendingJot) { _, pending in
            guard pending else { return }
            quickActions.pendingJot = false
            ideasFromQuickAction = true
            showIdeas = true
        }
        .onChange(of: deeplinkRouter?.pendingTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            deeplinkRouter?.pendingTab = nil
        }
        .task {
            // App-icon quick action, cold path: the flag was set in configurationForConnecting,
            // before this view existed, so onChange never saw a change.
            if quickActions.pendingJot {
                quickActions.pendingJot = false
                ideasFromQuickAction = true
                showIdeas = true
            }
            // v1 -> v2: carry the mis-named `startedAt` into `nextReminderAt`. Keyed on nil
            // rather than a run-once flag, so records arriving later from a device still on the
            // old build get carried across too.
            PersistenceController.backfillNextReminderAt(in: context)
            try? activityStore.seedDefaultsIfNeeded()
            try? logStore.backfillKindsIfNeeded()
            try? routineStore.seedDefaultsIfNeeded()
            // One-time: stamp isWalk on rows created before the flag existed. Once only, so
            // a user who later opts a task out of walk matching is never re-flipped.
            if !UserDefaults.standard.bool(forKey: "walk.isWalkBackfilled") {
                try? routineStore.backfillWalkFlags()
                UserDefaults.standard.set(true, forKey: "walk.isWalkBackfilled")
            }
            // Re-sync routine reminders on every launch: completions/skips/overrides (and
            // template edits synced from another device) all change what should fire.
            await RoutineReminderPlanner.resync(context: context, using: routineReminderScheduler)
            // Re-sync medication reminders on every launch. Cadences the calendar can't express
            // ("every 3 days", "every 2 months") are one-shot triggers that fire once and are
            // consumed, so without this they never re-arm; a reinstall or a medication synced
            // from another device likewise leaves nothing pending at all. Weekly/monthly meds
            // repeat natively and are merely re-asserted here, which is idempotent.
            await reminderScheduler.syncAll((try? medicationStore.medications()) ?? [])
            // Same for vaccination / vet-cadence / activity due reminders, which had no resync at
            // all: they were armed once when a record was saved and never re-derived, so a
            // reinstall or a record synced from another device left them silently missing.
            await DueReminderPlanner.resync(context: context, using: dueScheduler,
                                            cadenceMonths: vetCadenceMonths)
            // One-time walk-detection intro (skipped in UI tests: every test would trip it).
            if !UITestSupport.isUITest, !walkIntroShown {
                walkIntroShown = true
                showWalkIntro = true
            }
        }
        .sheet(isPresented: $showWalkIntro, onDismiss: {
            if pendingWalkSetup {
                pendingWalkSetup = false
                showWalkSetupSheet = true
            }
        }) {
            WalkIntroView(
                onSetUp: {
                    pendingWalkSetup = true
                    showWalkIntro = false
                },
                onLater: { showWalkIntro = false }
            )
        }
        .sheet(isPresented: $showWalkSetupSheet) {
            NavigationStack { WalkDetectionSettingsView() }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let data = pendingPhoto {
                pendingPhoto = nil
                capturedPhoto = CapturedPhoto(data: data)
            }
            if pendingLibraryFromCamera {
                pendingLibraryFromCamera = false
                showLibraryFallback = true
            }
        }) {
            CameraPicker(
                onCapture: { image in
                    if let jpeg = ImageDownscaler.scaledJPEG(from: image) {
                        pendingPhoto = jpeg
                    }
                },
                onFinish: { showCamera = false },
                onPickLibrary: {
                    pendingLibraryFromCamera = true
                    showCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibraryFallback, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = ImageDownscaler.scaledJPEG(from: image) {
                    await MainActor.run { capturedPhoto = CapturedPhoto(data: jpeg) }
                }
                await MainActor.run { libraryItem = nil }
            }
        }
        .sheet(item: $capturedPhoto, onDismiss: {
            if let handoff = pendingHandoff {
                pendingHandoff = nil
                activeHandoff = handoff
            }
        }) { photo in
            CaptureReviewView(
                photo: photo.data,
                logStore: logStore,
                activityStore: activityStore,
                medicationStore: medicationStore,
                dueScheduler: dueScheduler,
                onSaved: {},
                onHandoff: { kind in
                    pendingHandoff = HandoffPresentation(kind: kind, photo: photo.data)
                }
            )
        }
        .sheet(item: $activeHandoff) { handoff in
            switch handoff.kind {
            case .vaccine:
                VaccinationEditView(logStore: logStore, dueScheduler: dueScheduler,
                                     veterinarianStore: veterinarianStore, editing: nil,
                                     initialPhoto: handoff.photo)
            case .vet:
                VetVisitEditView(logStore: logStore, dueScheduler: dueScheduler,
                                  cadenceMonths: vetCadenceMonths,
                                  veterinarianStore: veterinarianStore, editing: nil,
                                  initialPhoto: handoff.photo)
            }
        }
    }
}
