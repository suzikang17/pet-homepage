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

    func schedule(_ reminder: PendingMedicationReminder) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let id = MedicationReminderIdentifier.requestID(for: reminder.medicationID)
        // Replace any existing reminder for this medication first.
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(medicationID: UUID) async {
        let id = MedicationReminderIdentifier.requestID(for: medicationID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func pendingMedicationIDs() async -> [UUID] {
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap { MedicationReminderIdentifier.medicationID(from: $0.identifier) }
    }
}
