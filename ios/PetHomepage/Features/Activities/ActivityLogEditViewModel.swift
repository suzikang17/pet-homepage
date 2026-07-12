// ios/PetHomepage/Features/Activities/ActivityLogEditViewModel.swift
import Foundation
import Observation

@Observable
final class ActivityLogEditViewModel {
    var availableTypes: [ActivityType] = []
    var selectedType: ActivityType?
    var performedAt: Date = Date()
    var hasEndTime: Bool = false
    var endedAt: Date = Date()
    var note: String = ""
    var hasCadence: Bool = false
    var intervalDays: Int = 0
    var pendingPhotos: [Data] = []
    var existingPhotos: [Photo] = []

    // Inline "+ New activity" fields.
    var newTypeName: String = ""
    var newTypeCategory: ActivityCategory = .other

    private let store: ActivityStore
    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler
    private let editing: LogEntry?

    init(logStore: LogStore, store: ActivityStore, dueScheduler: DueReminderScheduler, editing: LogEntry?) {
        self.logStore = logStore
        self.store = store
        self.dueScheduler = dueScheduler
        self.editing = editing
        availableTypes = (try? store.types()) ?? []
        if let log = editing {
            selectedType = log.activityType
            performedAt = log.performedAt
            hasEndTime = log.endedAt != nil
            endedAt = log.endedAt ?? log.performedAt
            note = log.note ?? ""
            intervalDays = Int(log.intervalDays)
            hasCadence = log.intervalDays > 0
            existingPhotos = log.photoArray
        } else if let first = availableTypes.first {
            selectType(first)
        }
    }

    var isValid: Bool { selectedType != nil }

    /// Whole minutes of the drafted span; nil while "Add end time" is off.
    var durationMinutes: Int? {
        guard hasEndTime else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(performedAt) / 60))
    }

    /// The end passed to the store: clamped so a start edited past the end can't crash the save.
    private var effectiveEndedAt: Date? {
        hasEndTime ? max(endedAt, performedAt) : nil
    }

    /// Adopt a type and pre-fill cadence from its default.
    func selectType(_ type: ActivityType) {
        selectedType = type
        intervalDays = Int(type.defaultIntervalDays)
        hasCadence = type.defaultIntervalDays > 0
    }

    /// Create a type from the inline fields and select it.
    func createAndSelectNewType() throws {
        let name = newTypeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let type = try store.createType(name: name, category: newTypeCategory, iconName: newTypeCategory.systemImage, defaultIntervalDays: 0)
        availableTypes = (try? store.types()) ?? []
        newTypeName = ""
        newTypeCategory = .other
        selectType(type)
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
        guard let type = selectedType else { return }
        let interval = hasCadence ? intervalDays : 0
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let noteOrNil = trimmedNote.isEmpty ? nil : trimmedNote

        // Capture the prior latest-of-type BEFORE logging, so we can cancel its reminder
        // (only the newest log of a type should hold a pending reminder).
        let priorLatest = editing == nil ? (try? logStore.latestLog(of: type)) : nil

        let log: LogEntry
        if let existing = editing {
            try logStore.updateActivity(existing, type: type, performedAt: performedAt,
                                        endedAt: effectiveEndedAt, note: noteOrNil,
                                        intervalDays: interval)
            log = existing
        } else {
            log = try logStore.logActivity(type: type, performedAt: performedAt,
                                           endedAt: effectiveEndedAt, note: noteOrNil,
                                           intervalDays: interval)
        }

        for data in pendingPhotos {
            try? logStore.addPhoto(to: log, imageData: data)
        }

        if let prior = priorLatest, prior.id != log.id {
            await dueScheduler.cancelActivity(prior)
        }
        await dueScheduler.syncActivity(log)
    }
}
