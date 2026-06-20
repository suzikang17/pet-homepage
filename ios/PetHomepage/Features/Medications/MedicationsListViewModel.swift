// ios/PetHomepage/Features/Medications/MedicationsListViewModel.swift
import Foundation
import Observation

struct MedicationRow: Identifiable {
    let id: UUID
    let medication: Medication
    let drugName: String
    let dosage: String
    let lastGiven: Date?
    let nextDue: Date?
    let refillDueAt: Date?
    let isRefillDueSoon: Bool
}

@Observable
final class MedicationsListViewModel {
    var rows: [MedicationRow] = []

    private let medicationStore: MedicationStore
    private let doseLogStore: DoseLogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let calendar: Calendar
    private let refillSoonWindowDays = 7

    init(medicationStore: MedicationStore,
         doseLogStore: DoseLogStore,
         reminderScheduler: MedicationReminderScheduler,
         calendar: Calendar = .current) {
        self.medicationStore = medicationStore
        self.doseLogStore = doseLogStore
        self.reminderScheduler = reminderScheduler
        self.calendar = calendar
    }

    /// True when at least one medication has a refill due within 7 days — useful for tab badge.
    var hasAnyRefillDueSoon: Bool {
        rows.contains { $0.isRefillDueSoon }
    }

    func load() throws {
        let now = Date()
        rows = try medicationStore.medications().map { med in
            MedicationRow(
                id: med.id,
                medication: med,
                drugName: med.drugName,
                dosage: med.dosage,
                lastGiven: try doseLogStore.lastGiven(for: med),
                nextDue: nextDue(for: med, now: now),
                refillDueAt: med.refillDueAt,
                isRefillDueSoon: isRefillDueSoon(med.refillDueAt, now: now)
            )
        }
    }

    func logDose(_ row: MedicationRow, at date: Date = Date()) async throws {
        try doseLogStore.logDose(for: row.medication, at: date)
        try load()
    }

    func delete(_ row: MedicationRow) async throws {
        await reminderScheduler.cancel(row.medication)
        try medicationStore.delete(row.medication)
        try load()
    }

    /// The medication's scheduleTime mapped onto today, or tomorrow if already passed.
    private func nextDue(for medication: Medication, now: Date) -> Date {
        let timeComponents = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        let todayAtTime = calendar.date(from: todayComponents) ?? now
        if todayAtTime > now {
            return todayAtTime
        }
        return calendar.date(byAdding: .day, value: 1, to: todayAtTime) ?? todayAtTime
    }

    private func isRefillDueSoon(_ refillDueAt: Date?, now: Date) -> Bool {
        guard let refillDueAt else { return false }
        guard let window = calendar.date(byAdding: .day, value: refillSoonWindowDays, to: now) else { return false }
        return refillDueAt <= window
    }
}
