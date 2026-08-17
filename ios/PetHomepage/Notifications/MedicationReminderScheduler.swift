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
    /// - weekly / monthly → a self-repeating calendar trigger (weekday / day-of-month), which
    ///   iOS re-fires unattended even if the app is never opened again,
    /// - any other cadence → a one-shot trigger on the next due date, re-armed by the resync
    ///   on save, dose log, and app launch.
    ///
    /// The repeating cases exist because a one-shot fires exactly once and is then consumed:
    /// a monthly preventative scheduled as a one-shot goes silent forever the moment the user
    /// dismisses its first banner without logging a dose in-app.
    func reminder(for medication: Medication) -> PendingReminder {
        let freq = MedFrequency(parsing: medication.frequency)
        let time = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        let hour = time.hour ?? 0
        let minute = time.minute ?? 0
        let title = "Time for meds"
        let body = "Give \(medication.drugName) (\(medication.dosage))"

        func pending(_ dateComponents: DateComponents?, repeats: Bool = false) -> PendingReminder {
            PendingReminder(kind: .medication, entityID: medication.id,
                            title: title, body: body, hour: hour, minute: minute,
                            dateComponents: dateComponents, repeats: repeats)
        }

        // A bare hour/minute trigger already repeats daily.
        if freq.interval <= 1, freq.unit == .day { return pending(nil) }

        let next = freq.nextOccurrence(after: now(), start: medication.nextReminder,
                                       time: medication.scheduleTime, calendar: calendar)

        // Single-unit cadences the calendar can express natively: let iOS repeat them, so the
        // chain survives the app being closed for months. Multi-unit intervals ("every 3 days",
        // "every 2 months") have no calendar equivalent and stay one-shot.
        if freq.interval == 1 {
            switch freq.unit {
            case .week:
                var comps = DateComponents()
                comps.weekday = calendar.component(.weekday, from: next)
                return pending(comps, repeats: true)
            case .month:
                // Guard on the ANCHOR's day-of-month, not the computed next occurrence:
                // nextOccurrence CLAMPS (Jan 31 + 1 month → Feb 28), so reading the day off
                // `next` would see 28 for a 31st-anchored med and silently pin it to the 28th
                // of every month thereafter. Days 29–31 have no honest repeating form — a
                // repeating trigger skips the months that lack them — so they stay one-shot.
                let anchorDay = calendar.component(.day, from: medication.nextReminder)
                if anchorDay <= 28 {
                    var comps = DateComponents()
                    comps.day = anchorDay
                    return pending(comps, repeats: true)
                }
            case .day:
                break // interval > 1: handled by the one-shot path below.
            }
        }

        return pending(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next))
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
