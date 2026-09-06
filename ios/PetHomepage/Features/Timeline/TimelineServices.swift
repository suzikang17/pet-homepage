// ios/PetHomepage/Features/Timeline/TimelineServices.swift
import Foundation

/// Everything the record stream and its row editors need to read and write.
///
/// Lives in its own file because it outlived the view it was declared in: `TimelineView` was
/// split into `LogStreamView` (now the Schedule tab's Log subtab) and `GalleryView`, and this
/// bundle is passed to both, plus Home's cadence sheet and every record editor.
struct TimelineServices {
    let medicationStore: MedicationStore
    let veterinarianStore: VeterinarianStore
    let diaryStore: DiaryStore
    let symptomEntryStore: SymptomEntryStore
    let recommendationStore: VetRecommendationStore
    let activityStore: ActivityStore
    let logStore: LogStore
    let reminderScheduler: MedicationReminderScheduler
    let dueScheduler: DueReminderScheduler
    let cadenceMonths: Int
    /// AI record scanning (PDF/photo → extraction → ingestion). Optional: nil disables the
    /// "Scan a record" menu entry (e.g. when the extract endpoint isn't configured).
    let extractionService: ExtractionService?
    let ingestionService: RecordIngestionService?

    /// Whether the "Scan a record" path is configured at all.
    var canScanRecords: Bool { extractionService != nil && ingestionService != nil }
}
