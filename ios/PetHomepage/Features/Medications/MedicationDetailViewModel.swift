// ios/PetHomepage/Features/Medications/MedicationDetailViewModel.swift
import Foundation
import Observation

/// Drives the medication detail page: the record's details plus its logged-dose history,
/// with one-tap dose logging. Editing the medication itself is delegated to MedicationEditView.
@Observable
final class MedicationDetailViewModel {
    let medication: Medication
    var doses: [DoseLog] = []

    private let doseLogStore: DoseLogStore

    init(medication: Medication, doseLogStore: DoseLogStore) {
        self.medication = medication
        self.doseLogStore = doseLogStore
        load()
    }

    var lastGiven: Date? { doses.first?.givenAt }
    var doseCount: Int { doses.count }

    /// Reload the dose history (also picks up field edits made in the edit sheet).
    func load() {
        doses = (try? doseLogStore.logs(for: medication)) ?? []
    }

    func logDose(at date: Date = Date()) {
        try? doseLogStore.logDose(for: medication, at: date)
        load()
    }

    func deleteDose(_ log: DoseLog) {
        try? doseLogStore.delete(log)
        load()
    }
}
