// ios/PetHomepage/Features/Capture/CaptureReviewViewModel.swift
import Foundation
import Observation

/// What a captured photo gets tagged as: nothing (plain diary entry), an activity occurrence,
/// a medication dose, or a health marker reading. Drives which LogStore create call `save()`
/// makes. Vaccine/vet visit are NOT tags here — they hand off to their own prefilled editors
/// instead of saving through this sheet (see `RecordHandoff`).
enum CaptureTag: Equatable {
    case none
    case activity(ActivityType)
    case medication(Medication)
    case marker(MarkerType)
}

/// Record kinds that require their full editor (required fields, so no instant-save from the
/// capture sheet): picking one closes the review sheet and hands the photo off to the matching
/// prefilled editor. See `ContentView`'s staged-photo/onDismiss presentation pattern.
enum RecordHandoff {
    case vaccine
    case vet
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

    /// Text-field-friendly value/unit for the `.marker` tag; only relevant while `tag` is
    /// `.marker`. Mirrors MarkerEditViewModel's validation and unit defaults.
    var markerValue: String = ""
    var markerUnit: String = ""

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

    /// Unit choices for a marker type (empty = unit-less). Mirrors MarkerEditViewModel's picker
    /// so capture-tagged markers get the same defaults.
    func unitOptions(for markerType: MarkerType) -> [String] {
        switch markerType {
        case .weight: ["lb", "kg"]
        case .temperature: ["°C", "°F"]
        case .appetite, .energy, .water, .other: []
        }
    }

    /// Records a user-driven tag choice (chip tap). Clears the ✨ suggestion marker unless the
    /// user happened to pick the same tag OCR already suggested. Picking a marker type (re)seeds
    /// its default unit.
    func pick(_ tag: CaptureTag) {
        self.tag = tag
        userPickedTag = true
        if suggestedTag != tag {
            suggestedTag = nil
        }
        if case .marker(let type) = tag {
            markerUnit = unitOptions(for: type).first ?? ""
        }
    }

    /// False only while `.marker` is tagged and `markerValue` isn't a valid finite number —
    /// blocks Save in the sheet until a real reading is entered.
    var isValid: Bool {
        guard case .marker = tag else { return true }
        guard let parsed = Double(markerValue.trimmingCharacters(in: .whitespaces)) else { return false }
        return parsed.isFinite
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
        case .marker(let type):
            guard let parsed = Double(markerValue.trimmingCharacters(in: .whitespaces)), parsed.isFinite else {
                throw CaptureReviewError.invalidMarkerValue
            }
            let trimmedUnit = markerUnit.trimmingCharacters(in: .whitespaces)
            entry = try logStore.logMarker(type: type,
                                           value: parsed,
                                           unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                                           recordedAt: performedAt)
        }
        try logStore.addPhoto(to: entry, imageData: photo)
    }
}

enum CaptureReviewError: Error {
    /// `.save()` was called while `.marker` was tagged but `markerValue` didn't parse — the UI
    /// should never allow this (Save is disabled via `isValid`), but `save()` guards it too.
    case invalidMarkerValue
}
