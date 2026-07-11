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

        // Actionable routine reminders: register the Done/Skip/Snooze category and route
        // notification responses into the store (works from the lock screen, app closed).
        let handler = RoutineActionHandler(context: controller.container.viewContext,
                                           scheduler: UNNotificationScheduler())
        notificationResponder = RoutineNotificationResponder(handler: handler)
        UNUserNotificationCenter.current().delegate = notificationResponder
        RoutineNotificationAction.registerCategories()
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
