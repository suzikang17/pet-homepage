// ios/PetHomepage/Notifications/UNNotificationScheduler.swift
import Foundation
import UserNotifications

/// Production adapter: the ONLY type that touches the real UNUserNotificationCenter.
/// Never exercised by unit tests (it would require user permission / a device).
final class UNNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(_ reminder: PendingReminder) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let trigger: UNCalendarNotificationTrigger
        if let date = reminder.dateComponents {
            // One-shot reminder on a specific calendar date (vaccination-due / vet-cadence),
            // fired at the reminder's hour/minute.
            var components = date
            components.hour = reminder.hour
            components.minute = reminder.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            // Daily repeating reminder (medications).
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        let id = ReminderIdentifier.requestID(kind: reminder.kind, entityID: reminder.entityID)
        center.removePendingNotificationRequests(withIdentifiers: [id]) // replace
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(kind: ReminderKind, entityID: UUID) async {
        let id = ReminderIdentifier.requestID(kind: kind, entityID: entityID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func pendingIDs(kind: ReminderKind) async -> [UUID] {
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap { request in
            guard let (parsedKind, id) = ReminderIdentifier.parse(request.identifier),
                  parsedKind == kind else { return nil }
            return id
        }
    }

    func cancelAll(kind: ReminderKind) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderIdentifier.prefix(for: kind)) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
