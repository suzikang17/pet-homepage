// ios/PetHomepage/Notifications/NotificationRouter.swift
import Foundation

/// Shared between the notification responder and ContentView so a notification TAP lands on
/// the right screen instead of wherever the app was last. Every notification the app sends —
/// routine + meal reminders, and walk events — is acted on in the Schedule tab, so a tap
/// routes there. @MainActor because it drives SwiftUI selection state.
@MainActor
@Observable
final class NotificationRouter {
    /// Tab tags mirror ContentView's TabView (`.tag`).
    enum Tab: Int { case home = 0, timeline = 1, schedule = 3, careTeam = 4 }

    /// Set by a notification tap; ContentView consumes it (switches tab) and clears it.
    var pendingTab: Int?

    /// Decide the destination for a tapped notification. Routine (`routine-reminder-…`) and
    /// walk (`walk-…`) notifications both act on the Schedule tab.
    func route(requestID: String) {
        if requestID.hasPrefix("routine-reminder-") || requestID.hasPrefix("walk-") {
            pendingTab = Tab.schedule.rawValue
        }
    }
}
