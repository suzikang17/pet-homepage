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

    /// The tag OCR suggested, so the view can show a ✨ marker on the matching chip. Cleared
    /// whenever the user picks a different tag than the one suggested.
    var suggestedTag: CaptureTag?
    private(set) var userPickedTag = false

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

    /// Records a user-driven tag choice (chip tap). Clears the ✨ suggestion marker unless the
    /// user happened to pick the same tag OCR already suggested.
    func pick(_ tag: CaptureTag) {
        self.tag = tag
        userPickedTag = true
        if suggestedTag != tag {
            suggestedTag = nil
        }
    }

    /// Runs on-device OCR against the photo and, on a match, pre-selects the corresponding chip —
    /// but only if the user hasn't already picked one and nothing is selected yet.
    func runSuggestion() async {
        var candidateNames: [String] = []
        var candidateTags: [CaptureTag] = []
        for med in activeMeds {
            candidateNames.append(med.drugName)
            candidateTags.append(.medication(med))
        }
        for type in availableTypes {
            candidateNames.append(type.name)
            candidateTags.append(.activity(type))
        }

        guard let index = await TagSuggester.suggest(photo: photo, candidateNames: candidateNames) else {
            return
        }
        let matched = candidateTags[index]

        await MainActor.run {
            guard !userPickedTag && tag == .none else { return }
            tag = matched
            suggestedTag = matched
        }
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
