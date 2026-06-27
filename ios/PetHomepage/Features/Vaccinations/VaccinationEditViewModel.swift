// ios/PetHomepage/Features/Vaccinations/VaccinationEditViewModel.swift
import Foundation
import Observation

@Observable
final class VaccinationEditViewModel {
    var vaccineName: String = ""
    var administeredAt: Date = Date()
    var hasNextDue: Bool = false
    var nextDueAt: Date = Date()
    var lotNumber: String = ""
    var administeredBy: String = ""
    var availableVets: [Veterinarian] = []
    var selectedVet: Veterinarian?
    var pendingPhotos: [Data] = []
    var existingPhotos: [Photo] = []

    private let store: VaccinationStore
    private let dueScheduler: DueReminderScheduler
    private let diaryStore: DiaryStore
    private let editing: Vaccination?

    init(store: VaccinationStore, dueScheduler: DueReminderScheduler,
         veterinarianStore: VeterinarianStore, diaryStore: DiaryStore, editing: Vaccination?) {
        self.store = store
        self.dueScheduler = dueScheduler
        self.diaryStore = diaryStore
        self.editing = editing
        if let vax = editing {
            vaccineName = vax.vaccineName
            administeredAt = vax.administeredAt ?? Date()
            if let due = vax.nextDueAt {
                hasNextDue = true
                nextDueAt = due
            }
            lotNumber = vax.lotNumber ?? ""
            administeredBy = vax.administeredBy ?? ""
        }
        availableVets = (try? veterinarianStore.veterinarians()) ?? []
        selectedVet = editing?.veterinarian
        existingPhotos = editing?.photoArray ?? []
    }

    var isValid: Bool {
        !vaccineName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func addPickedPhoto(_ data: Data) { pendingPhotos.append(data) }
    func removePending(at index: Int) {
        if pendingPhotos.indices.contains(index) { pendingPhotos.remove(at: index) }
    }
    func deleteExisting(_ photo: Photo) {
        try? diaryStore.deletePhoto(photo)
        existingPhotos.removeAll { $0 == photo }
    }

    func save() async throws {
        let due = hasNextDue ? nextDueAt : nil
        let lot = lotNumber.isEmpty ? nil : lotNumber
        let by = administeredBy.isEmpty ? nil : administeredBy

        let vaccination: Vaccination
        if let existing = editing {
            try store.update(existing, vaccineName: vaccineName, administeredAt: administeredAt,
                             nextDueAt: due, lotNumber: lot, administeredBy: by)
            vaccination = existing
        } else {
            vaccination = try store.create(vaccineName: vaccineName, administeredAt: administeredAt,
                                           nextDueAt: due, lotNumber: lot, administeredBy: by)
        }
        vaccination.veterinarian = selectedVet
        try? vaccination.managedObjectContext?.save()
        for data in pendingPhotos {
            try? diaryStore.addPhoto(toVaccination: vaccination, imageData: data)
        }
        await dueScheduler.syncVaccination(vaccination)
    }
}
