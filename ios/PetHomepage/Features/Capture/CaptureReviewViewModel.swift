// ios/PetHomepage/Features/Capture/CaptureReviewViewModel.swift
import Foundation
import Observation

/// What a captured photo gets tagged as: nothing (plain diary entry), an activity occurrence,
/// or a medication dose. Drives which LogStore create call `save()` makes.
enum CaptureTag: Equatable {
    case none
    case activity(ActivityType)
    case medication(Medication)
}

/// Backs the post-capture review-and-tag sheet: pick a tag, optional note/date, then log it
/// through LogStore and attach the photo. Mirrors ActivityLogEditViewModel's save-time reminder
/// handling for the `.activity` path so cadence/reminder behavior stays identical.
@Observable
final class CaptureReviewViewModel {
    let photo: Data
    var tag: CaptureTag = .none
    var note: String = ""
    var performedAt: Date = Date()
    var availableTypes: [ActivityType] = []
    var activeMeds: [Medication] = []

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler

    init(photo: Data,
         logStore: LogStore,
         activityStore: ActivityStore,
         medicationStore: MedicationStore,
         dueScheduler: DueReminderScheduler) {
        self.photo = photo
        self.logStore = logStore
        self.dueScheduler = dueScheduler
        availableTypes = (try? activityStore.types()) ?? []
        let now = Date()
        activeMeds = ((try? medicationStore.medications()) ?? []).filter { med in
            med.endedAt == nil || med.endedAt! > now
        }
    }

    private var noteOrNil: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func save() async throws {
        let entry: LogEntry
        switch tag {
        case .none:
            entry = try logStore.createDiary(performedAt: performedAt, note: noteOrNil)
        case .activity(let type):
            // Capture the prior latest-of-type BEFORE logging, so we can cancel its reminder —
            // mirrors ActivityLogEditViewModel.save() exactly.
            let priorLatest = try? logStore.latestLog(of: type)
            let log = try logStore.logActivity(type: type,
                                                performedAt: performedAt,
                                                note: noteOrNil,
                                                intervalDays: Int(type.defaultIntervalDays))
            if let prior = priorLatest, prior.id != log.id {
                await dueScheduler.cancelActivity(prior)
            }
            await dueScheduler.syncActivity(log)
            entry = log
        case .medication(let med):
            entry = try logStore.logDose(for: med, at: performedAt, note: noteOrNil)
        }
        try logStore.addPhoto(to: entry, imageData: photo)
    }
}
