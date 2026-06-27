// ios/PetHomepage/Mirror/SnapshotBuilder.swift
import CoreData
import Foundation

enum SnapshotBuilderError: Error, Equatable {
    /// No current pet — nothing to mirror.
    case noPet
}

/// Reads the existing stores and assembles a `MirrorSnapshot`. Reads only — it never
/// writes Core Data. The same `NSManagedObjectContext` the stores share is used for the
/// one fetch the stores don't expose (a medication's full dose-log list).
final class SnapshotBuilder {
    private let petStore: PetStore
    private let medicationStore: MedicationStore
    private let doseLogStore: DoseLogStore
    private let vaccinationStore: VaccinationStore
    private let vetVisitStore: VetVisitStore
    private let recommendationStore: VetRecommendationStore
    private let healthMarkerStore: HealthMarkerStore
    private let symptomEpisodeStore: SymptomEpisodeStore
    private let symptomEntryStore: SymptomEntryStore
    private let veterinarianStore: VeterinarianStore
    private let context: NSManagedObjectContext
    private let now: () -> Date

    init(petStore: PetStore,
         medicationStore: MedicationStore,
         doseLogStore: DoseLogStore,
         vaccinationStore: VaccinationStore,
         vetVisitStore: VetVisitStore,
         recommendationStore: VetRecommendationStore,
         healthMarkerStore: HealthMarkerStore,
         symptomEpisodeStore: SymptomEpisodeStore,
         symptomEntryStore: SymptomEntryStore,
         veterinarianStore: VeterinarianStore? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.petStore = petStore
        self.medicationStore = medicationStore
        self.doseLogStore = doseLogStore
        self.vaccinationStore = vaccinationStore
        self.vetVisitStore = vetVisitStore
        self.recommendationStore = recommendationStore
        self.healthMarkerStore = healthMarkerStore
        self.symptomEpisodeStore = symptomEpisodeStore
        self.symptomEntryStore = symptomEntryStore
        self.veterinarianStore = veterinarianStore ?? VeterinarianStore(context: petStore.context, petStore: petStore)
        // The pet's managedObjectContext is the shared context every store was built with.
        self.context = petStore.context
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
                doseLogs: try doseLogs(for: med).map { DoseLogSnapshot(id: $0.id, givenAt: $0.givenAt) },
                veterinarian: med.veterinarian?.name
            )
        }

        let vaccinations = try vaccinationStore.vaccinations().map { vax in
            VaccinationSnapshot(
                id: vax.id ?? UUID(),
                vaccineName: vax.vaccineName,
                administeredAt: vax.administeredAt,
                nextDueAt: vax.nextDueAt,
                lotNumber: vax.lotNumber,
                administeredBy: vax.administeredBy,
                veterinarian: vax.veterinarian?.name
            )
        }

        let vetVisits = try vetVisitStore.visits().map { visit in
            VetVisitSnapshot(
                id: visit.id,
                occurredAt: visit.occurredAt,
                clinicName: visit.clinicName,
                vetName: visit.vetName,
                reason: visit.reason,
                diagnosis: visit.diagnosis,
                treatmentNotes: visit.treatmentNotes,
                nextVisitDate: visit.nextVisitDate,
                recommendations: try recommendationStore.recommendations(for: visit).map {
                    RecommendationSnapshot(id: $0.id, date: $0.date, text: $0.text)
                },
                veterinarian: visit.veterinarian?.name
            )
        }

        let unlinkedRecommendations = try recommendationStore.unlinkedRecommendations().map {
            RecommendationSnapshot(id: $0.id, date: $0.date, text: $0.text)
        }

        let healthMarkers = try healthMarkerStore.markers().map {
            HealthMarkerSnapshot(
                id: $0.id,
                markerType: $0.markerType.rawValue,
                value: $0.value,
                unit: $0.unit,
                recordedAt: $0.recordedAt
            )
        }

        let symptomEpisodes = try symptomEpisodeStore.episodes().map { episode in
            SymptomEpisodeSnapshot(
                id: episode.id,
                category: episode.category.rawValue,
                title: episode.title,
                startedAt: episode.startedAt,
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
            careTeam: careTeam
        )
    }

    /// A medication's dose logs (oldest-first) — fetched directly because DoseLogStore
    /// exposes `lastGiven`/`doseCount` but not the full list.
    private func doseLogs(for medication: Medication) throws -> [DoseLog] {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(format: "medication == %@", medication)
        request.sortDescriptors = [NSSortDescriptor(key: "givenAt", ascending: true)]
        return try context.fetch(request)
    }
}
