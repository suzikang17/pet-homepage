// ios/PetHomepageTests/MirrorSnapshotTests.swift
import XCTest
@testable import PetHomepage

final class MirrorSnapshotTests: XCTestCase {
    private func sampleSnapshot() -> MirrorSnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return MirrorSnapshot(
            schemaVersion: 1,
            generatedAt: date,
            pet: PetSnapshot(id: UUID(), name: "Sandy", species: "dog",
                             breed: "mutt", dob: date, adoptionDate: nil),
            medications: [
                MedicationSnapshot(id: UUID(), drugName: "Apoquel", dosage: "16mg",
                                   frequency: "daily", scheduleTime: date,
                                   startedAt: date, endedAt: nil, refillDueAt: date,
                                   doseLogs: [DoseLogSnapshot(id: UUID(), givenAt: date)])
            ],
            vaccinations: [
                VaccinationSnapshot(id: UUID(), vaccineName: "Rabies",
                                    administeredAt: date, nextDueAt: date,
                                    lotNumber: "L1", administeredBy: "Dr. Vet")
            ],
            vetVisits: [
                VetVisitSnapshot(id: UUID(), occurredAt: date, clinicName: "Clinic",
                                 vetName: "Dr. Vet", reason: "checkup", diagnosis: nil,
                                 treatmentNotes: nil, nextVisitDate: date,
                                 recommendations: [RecommendationSnapshot(id: UUID(), date: date, text: "rest")])
            ],
            unlinkedRecommendations: [RecommendationSnapshot(id: UUID(), date: date, text: "call back")],
            healthMarkers: [
                HealthMarkerSnapshot(id: UUID(), markerType: "weight", value: 12.3,
                                     unit: "kg", recordedAt: date)
            ],
            symptomEpisodes: [
                SymptomEpisodeSnapshot(id: UUID(), category: "digestive", title: "tummy",
                                       startedAt: date, resolvedAt: nil, status: "active",
                                       entries: [SymptomEntrySnapshot(id: UUID(), date: date,
                                                 severity: "mild", note: "ok", suspectedCause: "food")])
            ],
            activityLogs: [
                ActivityLogSnapshot(id: UUID(), typeName: "Bath", category: "care",
                                    icon: "drop.fill", performedAt: date, note: "Used oatmeal shampoo",
                                    intervalDays: 30, nextDueAt: date)
            ]
        )
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = sampleSnapshot()
        let data = try MirrorSnapshot.encoder.encode(snapshot)
        let decoded = try MirrorSnapshot.decoder.decode(MirrorSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testTopLevelKeysAreSnakeCaseAndStable() throws {
        let data = try MirrorSnapshot.encoder.encode(sampleSnapshot())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"schema_version\""))
        XCTAssertTrue(json.contains("\"generated_at\""))
        XCTAssertTrue(json.contains("\"vet_visits\""))
        XCTAssertTrue(json.contains("\"unlinked_recommendations\""))
        XCTAssertTrue(json.contains("\"symptom_episodes\""))
        XCTAssertTrue(json.contains("\"activity_logs\""))
        XCTAssertTrue(json.contains("\"type_name\""))
    }

    func testNestedCollectionCountsSurviveRoundTrip() throws {
        let decoded = try MirrorSnapshot.decoder.decode(
            MirrorSnapshot.self,
            from: try MirrorSnapshot.encoder.encode(sampleSnapshot())
        )
        XCTAssertEqual(decoded.medications.first?.doseLogs.count, 1)
        XCTAssertEqual(decoded.vetVisits.first?.recommendations.count, 1)
        XCTAssertEqual(decoded.symptomEpisodes.first?.entries.count, 1)
        XCTAssertEqual(decoded.activityLogs.first?.typeName, "Bath")
    }
}
