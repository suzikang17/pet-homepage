// ios/PetHomepage/Mirror/SnapshotBuilder.swift
import CoreData
import Foundation

enum SnapshotBuilderError: Error, Equatable {
    /// No current pet — nothing to mirror.
    case noPet
}

/// Reads the existing stores and assembles a `MirrorSnapshot`. Reads only — it never
/// writes Core Data.
final class SnapshotBuilder {
    private let petStore: PetStore
    private let medicationStore: MedicationStore
    private let recommendationStore: VetRecommendationStore
    private let symptomEntryStore: SymptomEntryStore
    private let veterinarianStore: VeterinarianStore
    private let logStore: LogStore
    private let now: () -> Date

    init(petStore: PetStore,
         medicationStore: MedicationStore,
         recommendationStore: VetRecommendationStore,
         symptomEntryStore: SymptomEntryStore,
         veterinarianStore: VeterinarianStore? = nil,
         logStore: LogStore? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.petStore = petStore
        self.medicationStore = medicationStore
        self.recommendationStore = recommendationStore
        self.symptomEntryStore = symptomEntryStore
        self.veterinarianStore = veterinarianStore ?? VeterinarianStore(context: petStore.context, petStore: petStore)
        self.logStore = logStore ?? LogStore(context: petStore.context, petStore: petStore)
        self.now = now
    }

    func build() throws -> MirrorSnapshot {
        guard let pet = try petStore.currentPet() else { throw SnapshotBuilderError.noPet }

        let petSnapshot = PetSnapshot(
            id: pet.id,
            name: pet.name,
            species: pet.species,
            breed: pet.breed,
            dob: pet.dob,
            adoptionDate: pet.adoptionDate
        )

        let medications = try medicationStore.medications().map { med in
            MedicationSnapshot(
                id: med.id,
                drugName: med.drugName,
                dosage: med.dosage,
                frequency: med.frequency,
                scheduleTime: med.scheduleTime,
                startedAt: med.startedAt,
                endedAt: med.endedAt,
                refillDueAt: med.refillDueAt,
                doseLogs: try doseLogs(for: med).map { DoseLogSnapshot(id: $0.id, givenAt: $0.performedAt) },
                veterinarian: med.veterinarian?.name
            )
        }

        let vaccinations = try logStore.vaccines().map { vax in
            VaccinationSnapshot(
                id: vax.id,
                vaccineName: vax.title ?? "",
                administeredAt: vax.performedAt,
                nextDueAt: vax.nextDueAt,
                lotNumber: vax.lotNumber,
                administeredBy: vax.administeredBy,
                veterinarian: vax.veterinarian?.name
            )
        }

        let vetVisits = try logStore.vetVisits().map { visit in
            VetVisitSnapshot(
                id: visit.id,
                occurredAt: visit.performedAt,
                clinicName: visit.clinicName,
                vetName: visit.vetName,
                reason: visit.title,
                diagnosis: visit.diagnosis,
                treatmentNotes: visit.treatmentNotes,
                nextVisitDate: visit.nextDueAt,
                recommendations: try recommendationStore.recommendations(for: visit).map {
                    RecommendationSnapshot(id: $0.id, date: $0.date, text: $0.text)
                },
                veterinarian: visit.veterinarian?.name
            )
        }

        let unlinkedRecommendations = try recommendationStore.unlinkedRecommendations().map {
            RecommendationSnapshot(id: $0.id, date: $0.date, text: $0.text)
        }

        let healthMarkers = try logStore.markers().map {
            HealthMarkerSnapshot(
                id: $0.id,
                markerType: $0.markerType.rawValue,
                value: $0.value,
                unit: $0.unit,
                recordedAt: $0.performedAt
            )
        }

        let symptomEpisodes = try logStore.episodes().map { episode in
            SymptomEpisodeSnapshot(
                id: episode.id,
                category: episode.category.rawValue,
                title: episode.title,
                startedAt: episode.performedAt,
                resolvedAt: episode.resolvedAt,
                status: episode.status.rawValue,
                entries: try symptomEntryStore.entries(for: episode).map {
                    SymptomEntrySnapshot(
                        id: $0.id,
                        date: $0.date,
                        severity: $0.severity.rawValue,
                        note: $0.note,
                        suspectedCause: $0.suspectedCause
                    )
                }
            )
        }

        let careTeam = try veterinarianStore.veterinarians().map {
            VeterinarianSnapshot(id: $0.id, name: $0.name, clinic: $0.clinic, phone: $0.phone,
                                 email: $0.email, address: $0.address, website: $0.website, notes: $0.notes)
        }

        let diary = try logStore.diaryEntries().map {
            DiaryEntrySnapshot(id: $0.id, date: $0.performedAt, note: $0.note, photoCount: $0.photoArray.count)
        }

        let activityLogs = try logStore.activityLogs().compactMap { log -> ActivityLogSnapshot? in
            guard let type = log.activityType else { return nil }
            return ActivityLogSnapshot(
                id: log.id,
                typeName: type.name,
                category: type.categoryRaw,
                icon: type.iconName,
                performedAt: log.performedAt,
                note: log.note,
                intervalDays: Int(log.intervalDays),
                nextDueAt: log.nextDueAt
            )
        }

        return MirrorSnapshot(
            schemaVersion: MirrorSnapshot.currentSchemaVersion,
            generatedAt: now(),
            pet: petSnapshot,
            medications: medications,
            vaccinations: vaccinations,
            vetVisits: vetVisits,
            unlinkedRecommendations: unlinkedRecommendations,
            healthMarkers: healthMarkers,
            symptomEpisodes: symptomEpisodes,
            careTeam: careTeam,
            diary: diary,
            activityLogs: activityLogs
        )
    }

    /// A medication's dose logs, oldest-first (LogStore.doses returns newest-first).
    private func doseLogs(for medication: Medication) throws -> [LogEntry] {
        Array(try logStore.doses(for: medication).reversed())
    }
}
