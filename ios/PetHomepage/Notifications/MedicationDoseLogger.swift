// ios/PetHomepage/Notifications/MedicationDoseLogger.swift
import CoreData
import Foundation

/// The single implementation of "record a dose and move the cadence on."
///
/// This rule lives in exactly one place on purpose. It previously existed in three, and they
/// disagreed: PetProfileView's quick action logged the dose but advanced neither the cadence nor
/// the reminder, so a dose logged from Home left the next reminder pointing at a date that had
/// already passed. Divergent copies of this rule are what produced the original
/// fires-once-then-silent reminder bug.
final class MedicationDoseLogger {
    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let calendar: Calendar
    private let now: () -> Date

    init(logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.calendar = calendar
        self.now = now
    }

    /// The next reminder date if a dose is given at `dose`: one cadence interval later, at the
    /// medication's scheduled time of day. Pure — writes nothing.
    func nextDue(for medication: Medication, after dose: Date) -> Date {
        let freq = MedFrequency(parsing: medication.frequency)
        let stepped = calendar.date(byAdding: freq.unit.calendarComponent,
                                    value: freq.interval, to: dose) ?? dose
        let time = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                             second: 0, of: stepped) ?? stepped
    }

    /// Records the dose, advances the cadence, and re-syncs the reminder.
    ///
    /// Returns the new next-due date, or nil if this was deduped. Dedupe is same-calendar-day:
    /// acting on a notification still sitting on the lock screen after an in-app log must not
    /// record a second dose. No medication in this model is scheduled more than once a day.
    @MainActor
    @discardableResult
    func log(_ medication: Medication, at date: Date? = nil, note: String? = nil) async -> Date? {
        let given = date ?? now()
        if let last = try? logStore.lastDose(for: medication),
           calendar.isDate(last, inSameDayAs: given) {
            return nil
        }
        try? logStore.logDose(for: medication, at: given, note: note)
        // `startedAt` is this model's "next reminder date", not when the course began.
        let next = nextDue(for: medication, after: given)
        medication.startedAt = next
        try? medication.managedObjectContext?.save()
        await reminderScheduler.sync(medication)
        return next
    }
}
