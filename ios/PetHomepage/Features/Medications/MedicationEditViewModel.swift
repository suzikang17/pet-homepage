// ios/PetHomepage/Features/Medications/MedicationEditViewModel.swift
import Foundation
import Observation

@Observable
final class MedicationEditViewModel {
    var drugName: String = ""
    var dosage: String = ""
    var frequencyInterval: Int = 1
    var frequencyUnit: FrequencyUnit = .day
    var scheduleTime: Date = Date()

    /// The canonical label for the chosen cadence (e.g. "Daily", "Every 3 days").
    var frequencyLabel: String {
        MedFrequency(interval: frequencyInterval, unit: frequencyUnit).label
    }

    /// Default the next reminder to one cadence-interval from now, so it follows the chosen
    /// frequency rather than defaulting to today. Called when the user changes the frequency.
    func resetNextReminderFromFrequency(now: Date = Date()) {
        let component = frequencyUnit.calendarComponent
        startedAt = Calendar.current.date(byAdding: component, value: max(1, frequencyInterval), to: now) ?? now
    }

    var startedAt: Date = Date()
    var hasRefillDue: Bool = false
    var refillDueAt: Date = Date()
    var hasEnded: Bool = false
    var endedAt: Date = Date()

    private let store: MedicationStore
    private let reminderScheduler: MedicationReminderScheduler
    private let editing: Medication?

    init(store: MedicationStore,
         reminderScheduler: MedicationReminderScheduler,
         editing: Medication?) {
        self.store = store
        self.reminderScheduler = reminderScheduler
        self.editing = editing

        if let med = editing {
            drugName = med.drugName
            dosage = med.dosage
            let parsed = MedFrequency(parsing: med.frequency)
            frequencyInterval = parsed.interval
            frequencyUnit = parsed.unit
            scheduleTime = med.scheduleTime
            startedAt = med.startedAt
            if let refill = med.refillDueAt {
                hasRefillDue = true
                refillDueAt = refill
            }
            if let ended = med.endedAt {
                hasEnded = true
                endedAt = ended
            }
        }
    }

    var isValid: Bool {
        !drugName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save() async throws {
        let refill = hasRefillDue ? refillDueAt : nil
        let ended = hasEnded ? endedAt : nil

        let medication: Medication
        if let existing = editing {
            try store.update(existing,
                             drugName: drugName,
                             dosage: dosage,
                             frequency: frequencyLabel,
                             scheduleTime: scheduleTime,
                             startedAt: startedAt,
                             endedAt: ended,
                             refillDueAt: refill)
            medication = existing
        } else {
            // endedAt is passed atomically into create() — a single context.save().
            // Never use a separate store.update() for endedAt after create(): a crash
            // between the two saves would persist a record with endedAt=nil even when
            // hasEnded=true (the bug introduced in 180f092, fixed here in the green
            // phase of the Task 5 TDD remediation pair).
            medication = try store.create(drugName: drugName,
                                          dosage: dosage,
                                          frequency: frequencyLabel,
                                          scheduleTime: scheduleTime,
                                          startedAt: startedAt,
                                          endedAt: ended,
                                          refillDueAt: refill)
        }

        await reminderScheduler.sync(medication)
    }
}
