// ios/PetHomepage/Notifications/MedicationReminderScheduler.swift
import Foundation

/// Turns a Medication into a daily PendingReminder and drives the injected
/// NotificationScheduling. Pure enough to unit-test with a fake.
final class MedicationReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date

    init(scheduler: NotificationScheduling,
         calendar: Calendar = .current,
         now: @escaping () -> Date = { Date() }) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    /// Builds the reminder for a medication, following its frequency:
    /// - daily (every 1 day) → a self-repeating daily trigger at the scheduled time,
    /// - any other cadence → a one-shot trigger on the next due date (recomputed each sync,
    ///   which happens on save, dose log, and app launch).
    func reminder(for medication: Medication) -> PendingReminder {
        let freq = MedFrequency(parsing: medication.frequency)
        let time = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        let hour = time.hour ?? 0
        let minute = time.minute ?? 0
        let title = "Time for meds"
        let body = "Give \(medication.drugName) (\(medication.dosage))"

        if freq.interval <= 1, freq.unit == .day {
            return PendingReminder(kind: .medication, entityID: medication.id,
                                   title: title, body: body, hour: hour, minute: minute,
                                   dateComponents: nil)
        }

        let next = freq.nextOccurrence(after: now(), start: medication.startedAt,
                                       time: medication.scheduleTime, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        return PendingReminder(kind: .medication, entityID: medication.id,
                               title: title, body: body, hour: hour, minute: minute,
                               dateComponents: comps)
    }

    /// Whether a medication is currently active (should have a reminder).
    private func isActive(_ medication: Medication) -> Bool {
        guard let endedAt = medication.endedAt else { return true }
        return endedAt > Date()
    }

    /// Schedules the reminder if the medication is active, otherwise cancels it.
    func sync(_ medication: Medication) async {
        if isActive(medication) {
            await scheduler.schedule(reminder(for: medication))
        } else {
            await scheduler.cancel(kind: .medication, entityID: medication.id)
        }
    }

    /// Explicitly cancels a medication's reminder (e.g. on delete).
    func cancel(_ medication: Medication) async {
        await scheduler.cancel(kind: .medication, entityID: medication.id)
    }

    /// Syncs reminders for a full list of medications in one pass.
    func syncAll(_ medications: [Medication]) async {
        for medication in medications {
            await sync(medication)
        }
    }

    /// Cancels all pending reminders for every medication in the list (e.g. on bulk delete).
    func cancelAll(_ medications: [Medication]) async {
        for medication in medications {
            await cancel(medication)
        }
    }
}
