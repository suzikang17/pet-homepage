// ios/PetHomepage/Notifications/NotificationRouter.swift
import Foundation

/// Shared between the notification responder and ContentView so a notification TAP lands on
/// the right screen instead of wherever the app was last. Every notification the app sends —
/// routine + meal reminders, and walk events — is acted on in the Schedule tab, so a tap
/// routes there. @MainActor because it drives SwiftUI selection state.
@MainActor
@Observable
final class NotificationRouter {
    /// Tab tags mirror ContentView's TabView (`.tag`). The raw values are load-bearing and must
    /// not be renumbered when the tabs are reordered or renamed — `gallery` is tag 1 because
    /// that tab used to be the Timeline.
    enum Tab: Int { case home = 0, gallery = 1, schedule = 3, careTeam = 4 }

    /// Set by a notification tap; ContentView consumes it (switches tab) and clears it.
    var pendingTab: Int?

    /// Which Schedule subtab to open with, when the destination is that tab. Consumed and
    /// cleared by ScheduleView.
    var pendingScheduleTab: ScheduleTab?

    /// Decide the destination for a tapped notification.
    ///
    /// Routine (`routine-reminder-…`) and walk (`walk-…`) notifications act on the day's
    /// checklist, so they open Schedule on Today. Medication reminders
    /// (`medication-reminder-…`, `medicationSnooze-reminder-…`) act on the medication rows and
    /// the dose history — which used to mean tab 1. That tab is now the photo gallery, so they
    /// open Schedule on Log instead; without this a tapped dose reminder lands on pictures.
    func route(requestID: String) {
        if requestID.hasPrefix("routine-reminder-") || requestID.hasPrefix("walk-") {
            pendingTab = Tab.schedule.rawValue
            pendingScheduleTab = .today
        } else if requestID.hasPrefix("medication-reminder-")
                    || requestID.hasPrefix("medicationSnooze-reminder-") {
            pendingTab = Tab.schedule.rawValue
            pendingScheduleTab = .log
        }
    }
}
