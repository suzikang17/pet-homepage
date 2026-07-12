import SwiftUI
import UserNotifications

@main
struct PetHomepageApp: App {
    // `--uitest`: an in-memory store (no CloudKit) seeded deterministically below, instead of the
    // real `.shared` CloudKit-backed container. Seeding happens synchronously here, before
    // `ContentView` is ever constructed, so the first render already sees the seeded pet.
    let persistence: PersistenceController
    /// Retained for the app's lifetime — UNUserNotificationCenter holds its delegate weakly.
    let notificationResponder: RoutineNotificationResponder

    init() {
        let controller = PersistenceController(inMemory: UITestSupport.isUITest)
        if UITestSupport.isUITest {
            UITestSupport.seed(context: controller.container.viewContext)
        }
        persistence = controller

        // Actionable reminders: register the routine + walk categories and route notification
        // responses into the stores (works from the lock screen, app closed).
        let context = controller.container.viewContext
        let handler = RoutineActionHandler(context: context,
                                           scheduler: UNNotificationScheduler())
        let walkHandler = WalkActionHandler(sessions: WalkSessionStore(context: context),
                                            context: context)
        notificationResponder = RoutineNotificationResponder(handler: handler,
                                                             walkHandler: walkHandler)
        UNUserNotificationCenter.current().delegate = notificationResponder
        NotificationBootstrap.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .task {
                    // A system notification-permission alert would block UI tests waiting on it.
                    guard !UITestSupport.isUITest else { return }
                    await NotificationBootstrap.requestAuthorizationIfNeeded(
                        using: UNNotificationScheduler()
                    )
                }
        }
    }
}
