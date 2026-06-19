import SwiftUI

@main
struct PetHomepageApp: App {
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .task {
                    await NotificationBootstrap.requestAuthorizationIfNeeded(
                        using: UNNotificationScheduler()
                    )
                }
        }
    }
}
