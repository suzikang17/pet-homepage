// ios/PetHomepage/Notifications/NotificationScheduling.swift
import Foundation

/// The category of a scheduled reminder. The raw value is embedded in the
/// notification request identifier so schedule/cancel are idempotent per (kind, entityID).
enum ReminderKind: String, CaseIterable {
    case medication
    case vaccination
    case vetCadence
    case activity
    case routine
    /// A one-shot "snooze 30 min" re-fire of a routine reminder. Its own kind so scheduling a
    /// snooze can never replace the task's repeating trigger (they'd share an identifier
    /// otherwise), and so routine re-syncs (cancelAll(.routine)) leave pending snoozes alone.
    case routineSnooze
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
    /// With non-nil dateComponents: false = one-shot on that date (vaccination/vet-cadence),
    /// true = repeating on those components (weekly routine reminders, components = [weekday]).
    /// Ignored when dateComponents is nil (always the daily repeating medication trigger).
    let repeats: Bool

    init(kind: ReminderKind,
         entityID: UUID,
         title: String,
         body: String,
         hour: Int,
         minute: Int,
         dateComponents: DateComponents? = nil,
         repeats: Bool = false) {
        self.kind = kind
        self.entityID = entityID
        self.title = title
        self.body = body
        self.hour = hour
        self.minute = minute
        self.dateComponents = dateComponents
        self.repeats = repeats
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
/// schedule/cancel/replace are idempotent per (kind, entityID). Format: "<kind>-reminder-<uuid>",
/// with a "-w<weekday>" suffix for repeating weekly reminders so one entity's per-weekday
/// requests coexist instead of replacing each other.
enum ReminderIdentifier {
    static func prefix(for kind: ReminderKind) -> String {
        "\(kind.rawValue)-reminder-"
    }

    static func requestID(kind: ReminderKind, entityID: UUID) -> String {
        prefix(for: kind) + entityID.uuidString
    }

    /// The request ID for a specific reminder. Repeating-weekly reminders get a `-w<weekday>`
    /// suffix so one task's per-weekday requests coexist instead of replacing each other.
    static func requestID(for reminder: PendingReminder) -> String {
        let base = requestID(kind: reminder.kind, entityID: reminder.entityID)
        if reminder.repeats, let weekday = reminder.dateComponents?.weekday {
            return base + "-w\(weekday)"
        }
        return base
    }

    /// Every request ID a (kind, entityID) pair could own: the bare ID plus all weekday
    /// variants. Used by cancel — removing IDs that were never scheduled is harmless.
    static func requestIDs(kind: ReminderKind, entityID: UUID) -> [String] {
        let base = requestID(kind: kind, entityID: entityID)
        return [base] + (1...7).map { "\(base)-w\($0)" }
    }

    static func parse(_ requestID: String) -> (ReminderKind, UUID)? {
        // Strip an optional "-w<digit>" weekly suffix before parsing the UUID.
        var body = requestID
        if let range = body.range(of: #"-w[1-7]$"#, options: .regularExpression) {
            body.removeSubrange(range)
        }
        for kind in ReminderKind.allCases {
            let prefix = prefix(for: kind)
            if body.hasPrefix(prefix),
               let id = UUID(uuidString: String(body.dropFirst(prefix.count))) {
                return (kind, id)
            }
        }
        return nil
    }
}
