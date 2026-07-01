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

    init(medication: Medication, logStore: LogStore) {
        self.medication = medication
        self.logStore = logStore
        load()
    }

    var lastGiven: Date? { doses.first?.performedAt }
    var doseCount: Int { doses.count }

    /// Reload the dose history (also picks up field edits made in the edit sheet).
    func load() {
        doses = (try? logStore.doses(for: medication)) ?? []
    }

    func logDose(at date: Date = Date()) {
        try? logStore.logDose(for: medication, at: date)
        load()
    }

    func deleteDose(_ log: LogEntry) {
        try? logStore.delete(log)
        load()
    }
}
