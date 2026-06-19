// ios/PetHomepage/Features/Medications/MedicationEditViewModel.swift
import Foundation
import Observation

@Observable
final class MedicationEditViewModel {
    var drugName: String = ""
    var dosage: String = ""
    var frequency: String = "daily"
    var scheduleTime: Date = Date()
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
            frequency = med.frequency
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
                             frequency: frequency,
                             scheduleTime: scheduleTime,
                             startedAt: startedAt,
                             endedAt: ended,
                             refillDueAt: refill)
            medication = existing
        } else {
            medication = try store.create(drugName: drugName,
                                          dosage: dosage,
                                          frequency: frequency,
                                          scheduleTime: scheduleTime,
                                          startedAt: startedAt,
                                          refillDueAt: refill)
            if let ended {
                try store.update(medication,
                                 drugName: drugName,
                                 dosage: dosage,
                                 frequency: frequency,
                                 scheduleTime: scheduleTime,
                                 startedAt: startedAt,
                                 endedAt: ended,
                                 refillDueAt: refill)
            }
        }

        await reminderScheduler.sync(medication)
    }
}
