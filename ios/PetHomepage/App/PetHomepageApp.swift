import SwiftUI
import UserNotifications

@main
struct PetHomepageApp: App {
    /// Quick actions only: catches the app-icon "Jot an idea" long-press (see QuickActions.swift).
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var quickActionDelegate
    // `--uitest`: an in-memory store (no CloudKit) seeded deterministically below, instead of the
    // real `.shared` CloudKit-backed container. Seeding happens synchronously here, before
    // `ContentView` is ever constructed, so the first render already sees the seeded pet.
    let persistence: PersistenceController
    /// Retained for the app's lifetime — UNUserNotificationCenter holds its delegate weakly.
    let notificationResponder: RoutineNotificationResponder
    /// Routes a notification tap to the right tab; observed by ContentView.
    let deeplinkRouter: NotificationRouter
    /// Retained for the app's lifetime — owns the home geofence + motion feed.
    let walkDetector: WalkDetector
    /// Retained for the app's lifetime — owns the HealthKit workout observer (watch walks).
    let watchImporter: WatchWalkImporter
    let walkSessions: WalkSessionStore

    init() {
        let controller = PersistenceController(inMemory: UITestSupport.isUITest)
        if UITestSupport.isUITest {
            UITestSupport.seed(context: controller.container.viewContext)
        }
        persistence = controller

        // Actionable reminders: register the routine + walk categories and route notification
        // responses into the stores (works from the lock screen, app closed).
        let context = controller.container.viewContext
        let sessions = WalkSessionStore(context: context)
        walkSessions = sessions
        let handler = RoutineActionHandler(context: context,
                                           scheduler: UNNotificationScheduler())
        let walkHandler = WalkActionHandler(sessions: sessions, context: context)
        let medicationHandler = MedicationActionHandler(context: context,
                                                        scheduler: UNNotificationScheduler())
        let router = NotificationRouter()
        deeplinkRouter = router
        notificationResponder = RoutineNotificationResponder(handler: handler,
                                                             walkHandler: walkHandler,
                                                             medicationHandler: medicationHandler,
                                                             router: router)
        UNUserNotificationCenter.current().delegate = notificationResponder
        NotificationBootstrap.registerCategories()

        // Walk auto-detection: home geofence + motion prompts (no-op until the user sets a
        // home location and grants Always in Settings → Walk detection).
        walkDetector = WalkDetector(context: context, sessions: sessions)
        // Apple Watch walk import: re-arms the workout observer each launch (no-op until the
        // user turns it on in Settings → Walk detection).
        watchImporter = WatchWalkImporter(context: context, sessions: sessions)
        if !UITestSupport.isUITest {
            walkDetector.refreshMonitoring()
            watchImporter.refresh()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deeplinkRouter)
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .task {
                    // A system notification-permission alert would block UI tests waiting on it.
                    guard !UITestSupport.isUITest else { return }
                    await NotificationBootstrap.requestAuthorizationIfNeeded(
                        using: UNNotificationScheduler()
                    )
                    // A walk session forgotten for 4+ hours is saved open-ended; tell the
                    // user so they can fill in the end time.
                    if let entry = try? walkSessions.expireIfStale() {
                        WalkLiveActivityController.sync(active: nil, petName: "")
                        let content = UNMutableNotificationContent()
                        content.title = "Walk never ended"
                        content.body = "A walk was left running — it's saved without an end time. Tap to fix."
                        let request = UNNotificationRequest(
                            identifier: "walk-expired-\(entry.id.uuidString)",
                            content: content, trigger: nil)
                        try? await UNUserNotificationCenter.current().add(request)
                    }
                }
        }
    }
}
