// ios/PetHomepage/Features/Medications/MedicationDetailViewModel.swift
import Foundation
import Observation

/// Drives the medication detail page: the record's details plus its logged-dose history,
/// with one-tap dose logging. Editing the medication itself is delegated to MedicationEditView.
@Observable
final class MedicationDetailViewModel {
    let medication: Medication
    var doses: [LogEntry] = []

    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let calendar: Calendar

    init(medication: Medication,
         logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         calendar: Calendar = .current) {
        self.medication = medication
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.calendar = calendar
        load()
    }

    private var doseLogger: MedicationDoseLogger {
        MedicationDoseLogger(logStore: logStore, reminderScheduler: reminderScheduler,
                             calendar: calendar)
    }

    var lastGiven: Date? { doses.first?.performedAt }
    var doseCount: Int { doses.count }

    /// Reload the dose history (also picks up field edits made in the edit sheet).
    func load() {
        doses = (try? logStore.doses(for: medication)) ?? []
    }

    /// Routed through MedicationDoseLogger so this screen advances the cadence and re-syncs the
    /// reminder like every other dose path. It previously only wrote the LogEntry — harmless
    /// while nothing called it, and a silent reintroduction of the divergence the logger exists
    /// to prevent the moment anything did.
    ///
    /// `dedupe: false`: this is an explicit call with a caller-chosen date, not a stale banner.
    @MainActor
    func logDose(at date: Date = Date()) async {
        await doseLogger.log(medication, at: date, dedupe: false)
        load()
    }

    /// Deletes one logged dose and moves the cadence back to follow whatever dose is now newest.
    ///
    /// Without this the delete was a half-undo: the dose vanished from history while
    /// `medication.nextReminder` stayed advanced, so the next
    /// reminder pointed a full interval past a dose that no longer existed. Deleting an older
    /// dose recomputes to the same value, so this is safe to run unconditionally.
    @MainActor
    func deleteDose(_ log: LogEntry) async {
        try? logStore.delete(log)
        load()
        if let newest = doses.first {
            medication.nextReminder = doseLogger.nextDue(for: medication, after: newest.performedAt)
            try? medication.managedObjectContext?.save()
        }
        await reminderScheduler.sync(medication)
    }
}
