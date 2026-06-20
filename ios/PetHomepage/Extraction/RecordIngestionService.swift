// ios/PetHomepage/Extraction/RecordIngestionService.swift
import CoreData
import Foundation

/// What ingesting one ExtractionResult produced.
enum IngestionOutcome: Equatable {
    case vaccination(UUID)
    case vetVisit(UUID)
    case medicationStart(UUID)
    case unsupported(ExtractionEventType)
}

/// Writes an ExtractionResult into the right store(s) and persists the original
/// uploaded file via DocumentStore. The server `/api/extract` is deferred; this is
/// driven by an injected ExtractionService elsewhere, so it stays fully testable.
final class RecordIngestionService {
    private let vaccinationStore: VaccinationStore
    private let vetVisitStore: VetVisitStore
    private let medicationStore: MedicationStore
    private let documentStore: DocumentStore
    private let calendar: Calendar

    /// Parses day-only field dates (yyyy-MM-dd) in UTC to avoid time-zone drift.
    private let dayFormatter: DateFormatter

    init(vaccinationStore: VaccinationStore,
         vetVisitStore: VetVisitStore,
         medicationStore: MedicationStore,
         documentStore: DocumentStore,
         calendar: Calendar = .current) {
        self.vaccinationStore = vaccinationStore
        self.vetVisitStore = vetVisitStore
        self.medicationStore = medicationStore
        self.documentStore = documentStore
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    private func parseDay(_ string: String?) -> Date? {
        guard let string else { return nil }
        return dayFormatter.date(from: string)
    }

    /// Ingests one extracted event. When `originalFile` is provided, the bytes are saved
    /// through DocumentStore FIRST (the original is always retained, even for unsupported
    /// types), then the structured record is written for supported types.
    @discardableResult
    func ingest(_ result: ExtractionResult,
                originalFile: (data: Data, fileName: String)?) throws -> IngestionOutcome {
        if let file = originalFile {
            try documentStore.save(file.data, named: file.fileName)
        }

        switch result.fields {
        case .vaccination(let f):
            let vax = try vaccinationStore.create(
                vaccineName: f.vaccineName,
                administeredAt: parseDay(f.administeredAt) ?? result.occurredAt,
                nextDueAt: parseDay(f.nextDueAt),
                lotNumber: f.lotNumber,
                administeredBy: f.administeredBy
            )
            return .vaccination(vax.id ?? UUID())

        case .vetVisit(let f):
            let visit = try vetVisitStore.create(
                occurredAt: result.occurredAt,
                clinicName: f.clinicName,
                vetName: f.vetName,
                reason: f.reason,
                diagnosis: f.diagnosis,
                treatmentNotes: f.treatmentNotes,
                nextVisitDate: parseDay(f.nextVisitDate)
            )
            return .vetVisit(visit.id ?? UUID())

        case .medicationStart(let f):
            let med = try medicationStore.create(
                drugName: f.drugName,
                dosage: f.dosage ?? "",
                frequency: f.frequency ?? "daily",
                scheduleTime: result.occurredAt,
                startedAt: parseDay(f.startedAt) ?? result.occurredAt,
                endedAt: nil,
                refillDueAt: parseDay(f.refillDueAt)
            )
            return .medicationStart(med.id)

        case .medicationRefill, .weight, .symptomNote, .photo, .labResult, .procedure, .general:
            // Not yet mapped to a store in this phase — original file is still retained above.
            return .unsupported(result.eventType)
        }
    }
}
