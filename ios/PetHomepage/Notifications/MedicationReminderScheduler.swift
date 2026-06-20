// ios/PetHomepage/Notifications/MedicationReminderScheduler.swift
import Foundation

/// Turns a Medication into a daily PendingMedicationReminder and drives the
/// injected NotificationScheduling. Pure enough to unit-test with a fake.
final class MedicationReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar

    init(scheduler: NotificationScheduling, calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.calendar = calendar
    }

    /// Builds the daily reminder for a medication from its scheduleTime.
    func reminder(for medication: Medication) -> PendingMedicationReminder {
        let components = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        return PendingMedicationReminder(
            medicationID: medication.id,
            title: "Time for meds",
            body: "Give \(medication.drugName) (\(medication.dosage))",
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
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
            await scheduler.cancel(medicationID: medication.id)
        }
    }

    /// Explicitly cancels a medication's reminder (e.g. on delete).
    func cancel(_ medication: Medication) async {
        await scheduler.cancel(medicationID: medication.id)
    }

    /// Syncs reminders for a full list of medications in one pass:
    /// active ones are scheduled (or replaced), ended ones are cancelled.
    func syncAll(_ medications: [Medication]) async {
        for medication in medications {
            await sync(medication)
        }
    }
}
