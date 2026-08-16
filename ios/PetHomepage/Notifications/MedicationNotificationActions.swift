// ios/PetHomepage/Notifications/MedicationNotificationActions.swift
import CoreData
import Foundation
import UserNotifications

/// The actionable category attached to medication reminders: long-pressing the notification on
/// the lock screen offers Log dose / Snooze 1 hour, so a preventative can be recorded without
/// opening the app at all. Before this existed a medication reminder was a plain banner, and the
/// only way to log the dose — and therefore the only thing that re-armed a one-shot cadence —
/// was a four-tap journey through the Timeline.
enum MedicationNotificationAction {
    static let categoryID = "medicationReminder"
    static let logDose = "medicationLogDose"
    static let snooze = "medicationSnooze60"

    /// The medication category. Registered together with the routine + walk ones by
    /// NotificationBootstrap.registerCategories (setNotificationCategories replaces the set).
    static func categories() -> Set<UNNotificationCategory> {
        let logAction = UNNotificationAction(identifier: logDose, title: "Log dose")
        let snoozeAction = UNNotificationAction(identifier: snooze, title: "Snooze 1 hour")
        return [UNNotificationCategory(identifier: categoryID,
                                       actions: [logAction, snoozeAction],
                                       intentIdentifiers: [])]
    }
}

/// Applies a medication notification action to the data. Pure logic keyed by plain strings, so
/// tests never need a real UNNotificationResponse (which can't be constructed).
final class MedicationActionHandler {
    private let context: NSManagedObjectContext
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date

    init(context: NSManagedObjectContext,
         scheduler: NotificationScheduling,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.context = context
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    /// Routes a notification action. Both the original reminder and a snoozed re-fire resolve to
    /// the same medication.
    // @MainActor: the delegate invokes this from an arbitrary queue, but the whole chain touches
    // the main-queue viewContext.
    @MainActor
    func handle(actionID: String, requestID: String) async {
        guard let (kind, medicationID) = ReminderIdentifier.parse(requestID),
              kind == .medication || kind == .medicationSnooze,
              let medication = fetchMedication(medicationID) else { return }

        switch actionID {
        case MedicationNotificationAction.logDose:
            await logDose(for: medication)
        case MedicationNotificationAction.snooze:
            await scheduleSnooze(for: medication)
        default:
            break // plain tap (UNNotificationDefaultActionIdentifier) just opens the app
        }
    }

    /// Records the dose and advances the cadence to follow it — mirroring LogDoseViewModel.confirm()
    /// so the notification path and the in-app path leave identical state behind.
    @MainActor
    private func logDose(for medication: Medication) async {
        let logStore = LogStore(context: context, petStore: PetStore(context: context))

        // Dedupe: acting on a stale notification after the dose was already logged in-app must
        // not record a second one. Same-calendar-day is the right granularity — no medication in
        // this model is scheduled more than once a day.
        if let last = try? logStore.lastDose(for: medication),
           calendar.isDate(last, inSameDayAs: now()) {
            return
        }

        let given = now()
        try? logStore.logDose(for: medication, at: given, note: nil)
        // `startedAt` is this model's "next reminder date" (see MedicationDetailView), so stepping
        // it forward is what moves the cadence along.
        let freq = MedFrequency(parsing: medication.frequency)
        let stepped = calendar.date(byAdding: freq.unit.calendarComponent,
                                    value: freq.interval, to: given) ?? given
        let time = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        medication.startedAt = calendar.date(bySettingHour: time.hour ?? 9,
                                             minute: time.minute ?? 0,
                                             second: 0, of: stepped) ?? stepped
        try? context.save()

        let reminderScheduler = MedicationReminderScheduler(scheduler: scheduler,
                                                            calendar: calendar, now: now)
        await reminderScheduler.sync(medication)
    }

    /// One-shot re-fire an hour from now, under the dedicated snooze kind so it can never replace
    /// the medication's own (possibly repeating) trigger. The snoozed notification carries the
    /// same category, so it can itself be logged or snoozed again.
    @MainActor
    private func scheduleSnooze(for medication: Medication) async {
        let fireAt = now().addingTimeInterval(60 * 60)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: fireAt)
        let time = calendar.dateComponents([.hour, .minute], from: fireAt)
        let reminder = PendingReminder(kind: .medicationSnooze,
                                       entityID: medication.id,
                                       title: "Time for meds",
                                       body: "Give \(medication.drugName) (\(medication.dosage))",
                                       hour: time.hour ?? 9,
                                       minute: time.minute ?? 0,
                                       dateComponents: dateComponents,
                                       repeats: false)
        await scheduler.schedule(reminder)
    }

    private func fetchMedication(_ id: UUID) -> Medication? {
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
