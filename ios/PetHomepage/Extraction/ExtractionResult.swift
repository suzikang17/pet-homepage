// ios/PetHomepage/Extraction/ExtractionResult.swift
import Foundation

/// Swift mirror of lib/schemas/extraction.ts `ExtractionResultSchema`.
/// Keep these two in sync deliberately (shared/ is canonical — see the design Risks).
enum ExtractionEventType: String, Codable, Equatable {
    case vetVisit = "vet_visit"
    case vaccination
    case medicationStart = "medication_start"
    case medicationRefill = "medication_refill"
    case weight
    case symptomNote = "symptom_note"
    case photo
    case labResult = "lab_result"
    case procedure
    case general
}

// MARK: - Per-event field payloads (snake_case decoded via CodingKeys).
// `*_at` / `*_date` values are ISO day strings (yyyy-MM-dd) and stay String here;
// RecordIngestionService parses them. weight is `weight_kg` (Double).

struct VetVisitFields: Codable, Equatable {
    var clinicName: String?
    var vetName: String?
    var reason: String?
    var diagnosis: String?
    var treatmentNotes: String?
    var weightKg: Double?
    var nextVisitDate: String?
    enum CodingKeys: String, CodingKey {
        case clinicName = "clinic_name"
        case vetName = "vet_name"
        case reason
        case diagnosis
        case treatmentNotes = "treatment_notes"
        case weightKg = "weight_kg"
        case nextVisitDate = "next_visit_date"
    }
}

struct VaccinationFields: Codable, Equatable {
    var vaccineName: String
    var administeredAt: String
    var administeredBy: String?
    var lotNumber: String?
    var nextDueAt: String?
    enum CodingKeys: String, CodingKey {
        case vaccineName = "vaccine_name"
        case administeredAt = "administered_at"
        case administeredBy = "administered_by"
        case lotNumber = "lot_number"
        case nextDueAt = "next_due_at"
    }
}

struct MedicationStartFields: Codable, Equatable {
    var drugName: String
    var dosage: String?
    var frequency: String?
    var startedAt: String
    var refillDueAt: String?
    var prescribingVet: String?
    var notes: String?
    enum CodingKeys: String, CodingKey {
        case drugName = "drug_name"
        case dosage
        case frequency
        case startedAt = "started_at"
        case refillDueAt = "refill_due_at"
        case prescribingVet = "prescribing_vet"
        case notes
    }
}

struct MedicationRefillFields: Codable, Equatable {
    var drugName: String
    var refillDate: String
    var nextRefillDueAt: String?
    enum CodingKeys: String, CodingKey {
        case drugName = "drug_name"
        case refillDate = "refill_date"
        case nextRefillDueAt = "next_refill_due_at"
    }
}

struct WeightFields: Codable, Equatable {
    var weightKg: Double
    var source: String?
    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case source
    }
}

struct SymptomNoteFields: Codable, Equatable {
    var category: String?
    var severity: String?
    var bodyArea: String?
    enum CodingKeys: String, CodingKey {
        case category
        case severity
        case bodyArea = "body_area"
    }
}

struct PhotoFields: Codable, Equatable {
    var description: String?
    var tags: [String]?
}

struct LabResultRow: Codable, Equatable {
    var name: String
    var value: String
    var unit: String?
    var referenceRange: String?
    var flag: String?
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case unit
        case referenceRange = "reference_range"
        case flag
    }
}

struct LabResultFields: Codable, Equatable {
    var testType: String
    var results: [LabResultRow]?
    var interpretedBy: String?
    var notes: String?
    enum CodingKeys: String, CodingKey {
        case testType = "test_type"
        case results
        case interpretedBy = "interpreted_by"
        case notes
    }
}

struct ProcedureFields: Codable, Equatable {
    var procedureType: String
    var performedBy: String?
    var anesthesia: Bool?
    var recoveryNotes: String?
    var followUpDate: String?
    enum CodingKeys: String, CodingKey {
        case procedureType = "procedure_type"
        case performedBy = "performed_by"
        case anesthesia
        case recoveryNotes = "recovery_notes"
        case followUpDate = "follow_up_date"
    }
}

struct GeneralFields: Codable, Equatable {
    var summary: String?
}

/// The decoded per-type payload, selected by event_type (the discriminant).
enum ExtractionFields: Equatable {
    case vetVisit(VetVisitFields)
    case vaccination(VaccinationFields)
    case medicationStart(MedicationStartFields)
    case medicationRefill(MedicationRefillFields)
    case weight(WeightFields)
    case symptomNote(SymptomNoteFields)
    case photo(PhotoFields)
    case labResult(LabResultFields)
    case procedure(ProcedureFields)
    case general(GeneralFields)
}

/// One extracted health event. Mirrors the discriminated union: `event_type`
/// selects which `fields` payload is present.
struct ExtractionResult: Codable, Equatable {
    let eventType: ExtractionEventType
    let occurredAt: Date
    let title: String
    let notes: String?
    let fields: ExtractionFields

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case title
        case notes
        case fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try container.decode(ExtractionEventType.self, forKey: .eventType)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        switch eventType {
        case .vetVisit:         fields = .vetVisit(try container.decode(VetVisitFields.self, forKey: .fields))
        case .vaccination:      fields = .vaccination(try container.decode(VaccinationFields.self, forKey: .fields))
        case .medicationStart:  fields = .medicationStart(try container.decode(MedicationStartFields.self, forKey: .fields))
        case .medicationRefill: fields = .medicationRefill(try container.decode(MedicationRefillFields.self, forKey: .fields))
        case .weight:           fields = .weight(try container.decode(WeightFields.self, forKey: .fields))
        case .symptomNote:      fields = .symptomNote(try container.decode(SymptomNoteFields.self, forKey: .fields))
        case .photo:            fields = .photo(try container.decode(PhotoFields.self, forKey: .fields))
        case .labResult:        fields = .labResult(try container.decode(LabResultFields.self, forKey: .fields))
        case .procedure:        fields = .procedure(try container.decode(ProcedureFields.self, forKey: .fields))
        case .general:          fields = .general(try container.decode(GeneralFields.self, forKey: .fields))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        switch fields {
        case .vetVisit(let f):         try container.encode(f, forKey: .fields)
        case .vaccination(let f):      try container.encode(f, forKey: .fields)
        case .medicationStart(let f):  try container.encode(f, forKey: .fields)
        case .medicationRefill(let f): try container.encode(f, forKey: .fields)
        case .weight(let f):           try container.encode(f, forKey: .fields)
        case .symptomNote(let f):      try container.encode(f, forKey: .fields)
        case .photo(let f):            try container.encode(f, forKey: .fields)
        case .labResult(let f):        try container.encode(f, forKey: .fields)
        case .procedure(let f):        try container.encode(f, forKey: .fields)
        case .general(let f):          try container.encode(f, forKey: .fields)
        }
    }

    /// Shared decoder: top-level `occurred_at` is an ISO 8601 datetime.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The server may return one or more events for a single uploaded file.
struct ExtractionResponse: Codable, Equatable {
    let results: [ExtractionResult]
}
