// ios/PetHomepage/Notifications/NotificationScheduling.swift
import Foundation

/// The category of a scheduled reminder. The raw value is embedded in the
/// notification request identifier so schedule/cancel are idempotent per (kind, entityID).
enum ReminderKind: String {
    case medication
    case vaccination
    case vetCadence
    case activity
}

/// A single pending reminder, expressed independently of UserNotifications so
/// scheduling logic is pure and testable. A nil `dateComponents` means a DAILY
/// repeating trigger at `hour`/`minute` (medications); a non-nil `dateComponents`
/// means a ONE-SHOT trigger on that calendar date (vaccination-due / vet-cadence).
struct PendingReminder: Equatable {
    let kind: ReminderKind
    let entityID: UUID
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let dateComponents: DateComponents?

    init(kind: ReminderKind,
         entityID: UUID,
         title: String,
         body: String,
         hour: Int,
         minute: Int,
         dateComponents: DateComponents? = nil) {
        self.kind = kind
        self.entityID = entityID
        self.title = title
        self.body = body
        self.hour = hour
        self.minute = minute
        self.dateComponents = dateComponents
    }
}

// MARK: - Backward-compat (medication) shims
//
// These keep the existing medication source/tests compiling UNCHANGED while the
// underlying model is generalized. `PendingMedicationReminder` used to be its own
// struct with a `medicationID` field and a `(medicationID:title:body:hour:minute:)`
// initializer; it is now an alias for `PendingReminder` plus the conveniences below.

/// Back-compat alias: existing tests still name `PendingMedicationReminder`.
typealias PendingMedicationReminder = PendingReminder

extension PendingReminder {
    /// Back-compat accessor: medication code read `reminder.medicationID`.
    var medicationID: UUID { entityID }

    /// Back-compat initializer: `PendingMedicationReminder(medicationID:title:body:hour:minute:)`.
    /// A medication reminder is a daily repeating one (dateComponents == nil).
    init(medicationID: UUID, title: String, body: String, hour: Int, minute: Int) {
        self.init(kind: .medication,
                  entityID: medicationID,
                  title: title,
                  body: body,
                  hour: hour,
                  minute: minute,
                  dateComponents: nil)
    }
}

/// Abstraction over the system notification center so scheduling logic can be
/// unit-tested with a fake (no real UNUserNotificationCenter, no permission prompt).
protocol NotificationScheduling {
    /// Requests notification authorization; returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Schedules (or replaces) a reminder, keyed by (kind, entityID).
    func schedule(_ reminder: PendingReminder) async
    /// Cancels the pending reminder for a given (kind, entityID), if any.
    func cancel(kind: ReminderKind, entityID: UUID) async
    /// The entity IDs that currently have a pending reminder of the given kind.
    func pendingIDs(kind: ReminderKind) async -> [UUID]
    /// Cancels ALL pending reminders of the given kind.
    func cancelAll(kind: ReminderKind) async
}

// MARK: - Backward-compat protocol shims
//
// Default implementations so existing medication call sites compile against the
// generalized protocol without edits. UNNotificationScheduler and the fake get
// these for free; either may still override them.
extension NotificationScheduling {
    /// Back-compat: cancel a medication reminder by its medication ID.
    func cancel(medicationID: UUID) async {
        await cancel(kind: .medication, entityID: medicationID)
    }

    /// Back-compat: the medication IDs that currently have a pending reminder.
    func pendingMedicationIDs() async -> [UUID] {
        await pendingIDs(kind: .medication)
    }

    /// Back-compat: no-arg bulk cancel used by `NotificationBootstrap.cancelAllReminders`.
    /// Only medication reminders existed when this entry point was written, so it
    /// clears the `.medication` kind.
    func cancelAll() async {
        await cancelAll(kind: .medication)
    }
}

/// Deterministic request identifier shared by the real and fake schedulers, so
/// schedule/cancel/replace are idempotent per (kind, entityID). Format: "<kind>-reminder-<uuid>".
enum ReminderIdentifier {
    static func prefix(for kind: ReminderKind) -> String {
        "\(kind.rawValue)-reminder-"
    }

    static func requestID(kind: ReminderKind, entityID: UUID) -> String {
        prefix(for: kind) + entityID.uuidString
    }

    static func parse(_ requestID: String) -> (ReminderKind, UUID)? {
        for kind in [ReminderKind.medication, .vaccination, .vetCadence, .activity] {
            let prefix = prefix(for: kind)
            if requestID.hasPrefix(prefix),
               let id = UUID(uuidString: String(requestID.dropFirst(prefix.count))) {
                return (kind, id)
            }
        }
        return nil
    }
}
