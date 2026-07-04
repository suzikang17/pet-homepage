// ios/PetHomepage/Mirror/MirrorSnapshot.swift
import Foundation

/// A `Codable` value-type mirror of the full single-pet health record — the serializable
/// payload a future read-only web dashboard would render. NO Core Data here: `SnapshotBuilder`
/// reads the existing stores and fills these structs. The Convex backend + Next.js dashboard
/// are deferred; this type IS the contract they will consume (see the design's Phase 5).
struct MirrorSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var pet: PetSnapshot
    var medications: [MedicationSnapshot]
    var vaccinations: [VaccinationSnapshot]
    var vetVisits: [VetVisitSnapshot]
    var unlinkedRecommendations: [RecommendationSnapshot]
    var healthMarkers: [HealthMarkerSnapshot]
    var symptomEpisodes: [SymptomEpisodeSnapshot]
    var careTeam: [VeterinarianSnapshot] = []
    var diary: [DiaryEntrySnapshot] = []
    var activityLogs: [ActivityLogSnapshot] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case pet
        case medications
        case vaccinations
        case vetVisits = "vet_visits"
        case unlinkedRecommendations = "unlinked_recommendations"
        case healthMarkers = "health_markers"
        case symptomEpisodes = "symptom_episodes"
        case careTeam = "care_team"
        case diary
        case activityLogs = "activity_logs"
    }

    /// The current wire-format version. Bump when the shape changes so the web side can branch.
    /// v2 added `care_team` + a `veterinarian` (name) on medications/vaccinations/vet_visits.
    /// v3 added `diary` (entries with a photo_count; photo binaries stay on-device).
    /// v4 added `activity_logs` (flat, denormalized LogEntry occurrences with an activityType).
    static let currentSchemaVersion = 4

    /// Shared encoder: ISO-8601 dates, snake_case already handled by explicit CodingKeys.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Shared decoder mirroring `encoder` — used by round-trip tests (and the web side conceptually).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct PetSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var species: String
    var breed: String?
    var dob: Date?
    var adoptionDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, species, breed, dob
        case adoptionDate = "adoption_date"
    }
}

struct MedicationSnapshot: Codable, Equatable {
    var id: UUID
    var drugName: String
    var dosage: String
    var frequency: String
    var scheduleTime: Date
    var startedAt: Date
    var endedAt: Date?
    var refillDueAt: Date?
    var doseLogs: [DoseLogSnapshot]
    var veterinarian: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case drugName = "drug_name"
        case dosage
        case frequency
        case scheduleTime = "schedule_time"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case refillDueAt = "refill_due_at"
        case doseLogs = "dose_logs"
        case veterinarian
    }
}

struct DoseLogSnapshot: Codable, Equatable {
    var id: UUID
    var givenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case givenAt = "given_at"
    }
}

struct VaccinationSnapshot: Codable, Equatable {
    var id: UUID
    var vaccineName: String
    var administeredAt: Date?
    var nextDueAt: Date?
    var lotNumber: String?
    var administeredBy: String?
    var veterinarian: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case vaccineName = "vaccine_name"
        case administeredAt = "administered_at"
        case nextDueAt = "next_due_at"
        case lotNumber = "lot_number"
        case administeredBy = "administered_by"
        case veterinarian
    }
}

struct VetVisitSnapshot: Codable, Equatable {
    var id: UUID
    var occurredAt: Date
    var clinicName: String?
    var vetName: String?
    var reason: String?
    var diagnosis: String?
    var treatmentNotes: String?
    var nextVisitDate: Date?
    var recommendations: [RecommendationSnapshot]
    var veterinarian: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt = "occurred_at"
        case clinicName = "clinic_name"
        case vetName = "vet_name"
        case reason
        case diagnosis
        case treatmentNotes = "treatment_notes"
        case nextVisitDate = "next_visit_date"
        case recommendations
        case veterinarian
    }
}

struct RecommendationSnapshot: Codable, Equatable {
    var id: UUID
    var date: Date
    var text: String
}

struct VeterinarianSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var clinic: String?
    var phone: String?
    var email: String?
    var address: String?
    var website: String?
    var notes: String?
}

struct DiaryEntrySnapshot: Codable, Equatable {
    var id: UUID
    var date: Date
    var note: String?
    var photoCount: Int

    enum CodingKeys: String, CodingKey {
        case id, date, note
        case photoCount = "photo_count"
    }
}

struct ActivityLogSnapshot: Codable, Equatable {
    var id: UUID
    var typeName: String
    var category: String
    var icon: String
    var performedAt: Date
    var note: String?
    var intervalDays: Int
    var nextDueAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case typeName = "type_name"
        case category
        case icon
        case performedAt = "performed_at"
        case note
        case intervalDays = "interval_days"
        case nextDueAt = "next_due_at"
    }
}

struct HealthMarkerSnapshot: Codable, Equatable {
    var id: UUID
    var markerType: String
    var value: Double
    var unit: String?
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case markerType = "marker_type"
        case value
        case unit
        case recordedAt = "recorded_at"
    }
}

struct SymptomEpisodeSnapshot: Codable, Equatable {
    var id: UUID
    var category: String
    var title: String?
    var startedAt: Date
    var resolvedAt: Date?
    var status: String
    var entries: [SymptomEntrySnapshot]

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case title
        case startedAt = "started_at"
        case resolvedAt = "resolved_at"
        case status
        case entries
    }
}

struct SymptomEntrySnapshot: Codable, Equatable {
    var id: UUID
    var date: Date
    var severity: String
    var note: String?
    var suspectedCause: String?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case severity
        case note
        case suspectedCause = "suspected_cause"
    }
}
