// ios/PetHomepage/Features/Medications/LogDoseViewModel.swift
import Foundation
import Observation

/// Drives the "log a dose" flow: edit when it was given + an optional note, preview the next
/// reminder, then on confirm record the dose AND reschedule the next reminder to follow it.
@Observable
final class LogDoseViewModel {
    let medication: Medication
    var givenAt: Date = Date()
    var note: String = ""
    private(set) var isConfirmed = false
    private(set) var confirmedNextReminder: Date?
    private(set) var doseCount: Int = 0

    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler

    init(medication: Medication, logStore: LogStore, reminderScheduler: MedicationReminderScheduler) {
        self.medication = medication
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
    }

    var frequency: MedFrequency { MedFrequency(parsing: medication.frequency) }

    /// When the next reminder lands if this dose is logged: one cadence-interval after the dose,
    /// at the medication's scheduled time of day.
    func nextReminder(after dose: Date? = nil, calendar: Calendar = .current) -> Date {
        let d = dose ?? givenAt
        let stepped = calendar.date(byAdding: frequency.unit.calendarComponent,
                                    value: frequency.interval, to: d) ?? d
        let t = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        return calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: stepped) ?? stepped
    }

    @MainActor
    func confirm() async {
        let next = nextReminder()
        try? logStore.logDose(for: medication, at: givenAt, note: note)
        // Reschedule the next reminder to follow this dose.
        medication.startedAt = next
        try? medication.managedObjectContext?.save()
        await reminderScheduler.sync(medication)
        doseCount = (try? logStore.doseCount(for: medication)) ?? 0
        confirmedNextReminder = next
        isConfirmed = true
    }
}
