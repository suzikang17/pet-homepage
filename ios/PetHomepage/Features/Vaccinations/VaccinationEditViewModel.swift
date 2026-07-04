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

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler
    private let editing: LogEntry?

    init(logStore: LogStore, dueScheduler: DueReminderScheduler,
         veterinarianStore: VeterinarianStore, editing: LogEntry?) {
        self.logStore = logStore
        self.dueScheduler = dueScheduler
        self.editing = editing
        if let vax = editing {
            vaccineName = vax.title ?? ""
            administeredAt = vax.performedAt
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
        try? logStore.deletePhoto(photo)
        existingPhotos.removeAll { $0 == photo }
    }

    func save() async throws {
        let due = hasNextDue ? nextDueAt : nil
        let lot = lotNumber.isEmpty ? nil : lotNumber
        let by = administeredBy.isEmpty ? nil : administeredBy

        let vaccination: LogEntry
        if let existing = editing {
            try logStore.updateVaccine(existing, name: vaccineName, performedAt: administeredAt,
                                       nextDueAt: due, lotNumber: lot, administeredBy: by)
            vaccination = existing
        } else {
            vaccination = try logStore.logVaccine(name: vaccineName, performedAt: administeredAt,
                                                  nextDueAt: due, lotNumber: lot, administeredBy: by)
        }
        vaccination.veterinarian = selectedVet
        try? vaccination.managedObjectContext?.save()
        for data in pendingPhotos {
            try? logStore.addPhoto(to: vaccination, imageData: data)
        }
        await dueScheduler.syncVaccination(vaccination)
    }
}
