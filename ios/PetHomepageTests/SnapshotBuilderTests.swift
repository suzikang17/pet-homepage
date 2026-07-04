// ios/PetHomepageTests/SnapshotBuilderTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class SnapshotBuilderTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var medicationStore: MedicationStore!
    private var logStore: LogStore!
    private var vetVisitStore: VetVisitStore!
    private var recommendationStore: VetRecommendationStore!
    private var healthMarkerStore: HealthMarkerStore!
    private var symptomEpisodeStore: SymptomEpisodeStore!
    private var symptomEntryStore: SymptomEntryStore!
    private var activityStore: ActivityStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        medicationStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        recommendationStore = VetRecommendationStore(context: context)
        healthMarkerStore = HealthMarkerStore(context: context, petStore: petStore)
        symptomEpisodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
        symptomEntryStore = SymptomEntryStore(context: context)
        activityStore = ActivityStore(context: context, petStore: petStore)
    }

    private func makeBuilder() -> SnapshotBuilder {
        SnapshotBuilder(
            petStore: petStore,
            medicationStore: medicationStore,
            vetVisitStore: vetVisitStore,
            recommendationStore: recommendationStore,
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            symptomEntryStore: symptomEntryStore,
            logStore: logStore,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testBuildThrowsWhenNoPet() {
        let builder = makeBuilder()
        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertEqual(error as? SnapshotBuilderError, .noPet)
        }
    }

    func testBuildIncludesCareTeamAndPerRecordVet() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try petStore.createPet(name: "Sandy", species: "dog")
        let vetStore = VeterinarianStore(context: context, petStore: petStore)
        let vet = try vetStore.create(name: "Dr. Ruth", clinic: "Maple Vet")
        let med = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                             scheduleTime: date, startedAt: date, refillDueAt: nil)
        med.veterinarian = vet
        try context.save()

        let snapshot = try makeBuilder().build()

        XCTAssertEqual(snapshot.careTeam.count, 1)
        XCTAssertEqual(snapshot.careTeam.first?.name, "Dr. Ruth")
        XCTAssertEqual(snapshot.careTeam.first?.clinic, "Maple Vet")
        XCTAssertEqual(snapshot.medications.first?.veterinarian, "Dr. Ruth")
        XCTAssertEqual(snapshot.schemaVersion, MirrorSnapshot.currentSchemaVersion)
    }

    func testBuildIncludesDiaryWithPhotoCounts() throws {
        try petStore.createPet(name: "Sandy", species: "dog")
        let entry = try logStore.createDiary(performedAt: Date(timeIntervalSince1970: 1_700_000_000), note: "Beach day")
        try logStore.addPhoto(to: entry, imageData: Data([0x1]))

        let snapshot = try makeBuilder().build()

        XCTAssertEqual(snapshot.diary.count, 1)
        XCTAssertEqual(snapshot.diary.first?.note, "Beach day")
        XCTAssertEqual(snapshot.diary.first?.photoCount, 1)
        XCTAssertEqual(snapshot.schemaVersion, MirrorSnapshot.currentSchemaVersion)
    }

    func testBuildIncludesActivityLogsWithNextDueStamped() throws {
        try petStore.createPet(name: "Sandy", species: "dog")
        let type = try activityStore.createType(name: "Bath", category: .care,
                                                iconName: "drop.fill", defaultIntervalDays: 30)
        let performedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try logStore.logActivity(type: type, performedAt: performedAt, note: "Used oatmeal shampoo", intervalDays: 30)

        let snapshot = try makeBuilder().build()

        XCTAssertEqual(snapshot.activityLogs.count, 1)
        let log = try XCTUnwrap(snapshot.activityLogs.first)
        XCTAssertEqual(log.typeName, "Bath")
        XCTAssertEqual(log.category, "care")
        XCTAssertEqual(log.icon, "drop.fill")
        XCTAssertEqual(log.performedAt, performedAt)
        XCTAssertEqual(log.note, "Used oatmeal shampoo")
        XCTAssertEqual(log.intervalDays, 30)
        XCTAssertEqual(log.nextDueAt, Calendar.current.date(byAdding: .day, value: 30, to: performedAt))
        XCTAssertEqual(snapshot.schemaVersion, MirrorSnapshot.currentSchemaVersion)
    }

    func testBuildCapturesFullRecordWithCorrectCounts() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try petStore.createPet(name: "Sandy", species: "dog")

        let med = try medicationStore.create(drugName: "Apoquel", dosage: "16mg",
                                             frequency: "daily", scheduleTime: date,
                                             startedAt: date, refillDueAt: date)
        try logStore.logDose(for: med, at: date)
        try logStore.logDose(for: med, at: date.addingTimeInterval(86_400))

        try logStore.logVaccine(name: "Rabies", performedAt: date,
                                nextDueAt: date, lotNumber: "L1", administeredBy: "Dr. Vet")

        let visit = try vetVisitStore.create(occurredAt: date, clinicName: "Clinic",
                                             vetName: "Dr. Vet", reason: "checkup",
                                             diagnosis: nil, treatmentNotes: nil, nextVisitDate: date)
        try recommendationStore.create(text: "rest", date: date, vetVisit: visit)
        try recommendationStore.create(text: "call back", date: date, vetVisit: nil)

        try healthMarkerStore.create(markerType: .weight, value: 12.3, unit: "kg", recordedAt: date)
        try healthMarkerStore.create(markerType: .energy, value: 3, unit: nil, recordedAt: date)

        let episode = try symptomEpisodeStore.start(category: .digestive, title: "tummy", startedAt: date)
        try symptomEntryStore.addEntry(to: episode, date: date, severity: .mild,
                                       note: "ok", suspectedCause: "food")

        let snapshot = try makeBuilder().build()

        XCTAssertEqual(snapshot.schemaVersion, MirrorSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.generatedAt, date)
        XCTAssertEqual(snapshot.pet.name, "Sandy")
        XCTAssertEqual(snapshot.pet.species, "dog")

        XCTAssertEqual(snapshot.medications.count, 1)
        XCTAssertEqual(snapshot.medications.first?.drugName, "Apoquel")
        XCTAssertEqual(snapshot.medications.first?.doseLogs.count, 2)

        XCTAssertEqual(snapshot.vaccinations.count, 1)
        XCTAssertEqual(snapshot.vaccinations.first?.vaccineName, "Rabies")

        XCTAssertEqual(snapshot.vetVisits.count, 1)
        XCTAssertEqual(snapshot.vetVisits.first?.recommendations.count, 1)
        XCTAssertEqual(snapshot.vetVisits.first?.recommendations.first?.text, "rest")

        XCTAssertEqual(snapshot.unlinkedRecommendations.count, 1)
        XCTAssertEqual(snapshot.unlinkedRecommendations.first?.text, "call back")

        XCTAssertEqual(snapshot.healthMarkers.count, 2)
        XCTAssertTrue(snapshot.healthMarkers.contains { $0.markerType == "weight" && $0.value == 12.3 })

        XCTAssertEqual(snapshot.symptomEpisodes.count, 1)
        XCTAssertEqual(snapshot.symptomEpisodes.first?.status, "active")
        XCTAssertEqual(snapshot.symptomEpisodes.first?.entries.count, 1)
        XCTAssertEqual(snapshot.symptomEpisodes.first?.entries.first?.severity, "mild")
    }

    func testBuiltSnapshotEncodesAndDecodes() throws {
        try petStore.createPet(name: "Max", species: "cat")
        let snapshot = try makeBuilder().build()
        let data = try MirrorSnapshot.encoder.encode(snapshot)
        let decoded = try MirrorSnapshot.decoder.decode(MirrorSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
