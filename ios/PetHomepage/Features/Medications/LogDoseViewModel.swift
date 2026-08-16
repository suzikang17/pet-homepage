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

    private var doseLogger: MedicationDoseLogger {
        MedicationDoseLogger(logStore: logStore, reminderScheduler: reminderScheduler)
    }

    /// When the next reminder lands if this dose is logged.
    func nextReminder(after dose: Date? = nil, calendar: Calendar = .current) -> Date {
        MedicationDoseLogger(logStore: logStore, reminderScheduler: reminderScheduler,
                             calendar: calendar)
            .nextDue(for: medication, after: dose ?? givenAt)
    }

    @MainActor
    func confirm() async {
        let next = await doseLogger.log(medication, at: givenAt, note: note)
        doseCount = (try? logStore.doseCount(for: medication)) ?? 0
        confirmedNextReminder = next ?? nextReminder()
        isConfirmed = true
    }
}
