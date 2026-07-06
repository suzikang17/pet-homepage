import SwiftUI

@main
struct PetHomepageApp: App {
    // `--uitest`: an in-memory store (no CloudKit) seeded deterministically below, instead of the
    // real `.shared` CloudKit-backed container. Seeding happens synchronously here, before
    // `ContentView` is ever constructed, so the first render already sees the seeded pet.
    let persistence: PersistenceController = {
        let controller = PersistenceController(inMemory: UITestSupport.isUITest)
        if UITestSupport.isUITest {
            UITestSupport.seed(context: controller.container.viewContext)
        }
        return controller
    }()

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
