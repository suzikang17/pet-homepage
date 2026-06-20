// ios/PetHomepageTests/RecordIngestionServiceTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RecordIngestionServiceTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var vaxStore: VaccinationStore!
    private var vetVisitStore: VetVisitStore!
    private var medStore: MedicationStore!
    private var documentStore: DocumentStore!
    private var baseURL: URL!
    private var service: RecordIngestionService!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vaxStore = VaccinationStore(context: context, petStore: petStore)
        vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        medStore = MedicationStore(context: context, petStore: petStore)
        baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        documentStore = DocumentStore(baseURL: baseURL)
        service = RecordIngestionService(vaccinationStore: vaxStore,
                                         vetVisitStore: vetVisitStore,
                                         medicationStore: medStore,
                                         documentStore: documentStore,
                                         calendar: Calendar(identifier: .gregorian))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    private func decode(_ json: String) throws -> ExtractionResult {
        try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data(json.utf8))
    }

    func testIngestVaccinationWritesRecordAndSavesFile() throws {
        let result = try decode("""
        {
          "event_type": "vaccination",
          "occurred_at": "2026-03-01T10:00:00Z",
          "title": "Rabies",
          "fields": { "vaccine_name": "Rabies", "administered_at": "2026-03-01", "next_due_at": "2027-03-01", "lot_number": "L7", "administered_by": "Dr. V" }
        }
        """)

        let outcome = try service.ingest(result, originalFile: (Data("pdf".utf8), "rabies.pdf"))

        guard case .vaccination = outcome else { return XCTFail("expected .vaccination outcome") }
        let saved = try vaxStore.vaccinations()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.vaccineName, "Rabies")
        XCTAssertEqual(saved.first?.lotNumber, "L7")
        XCTAssertNotNil(saved.first?.nextDueAt)
        XCTAssertEqual(try documentStore.read(named: "rabies.pdf"), Data("pdf".utf8))
    }

    func testIngestVetVisitWritesRecord() throws {
        let result = try decode("""
        {
          "event_type": "vet_visit",
          "occurred_at": "2026-02-14T09:30:00Z",
          "title": "Checkup",
          "fields": { "clinic_name": "Paws", "vet_name": "Dr. V", "reason": "Exam", "diagnosis": "Healthy", "treatment_notes": "None", "next_visit_date": "2026-08-14" }
        }
        """)

        let outcome = try service.ingest(result, originalFile: nil)

        guard case .vetVisit = outcome else { return XCTFail("expected .vetVisit outcome") }
        let saved = try vetVisitStore.visits()
        XCTAssertEqual(saved.first?.clinicName, "Paws")
        XCTAssertEqual(saved.first?.diagnosis, "Healthy")
        XCTAssertNotNil(saved.first?.nextVisitDate)
    }

    func testIngestMedicationStartWritesRecord() throws {
        let result = try decode("""
        {
          "event_type": "medication_start",
          "occurred_at": "2026-01-05T08:00:00Z",
          "title": "Apoquel",
          "fields": { "drug_name": "Apoquel", "dosage": "16mg", "frequency": "daily", "started_at": "2026-01-05", "refill_due_at": "2026-02-05" }
        }
        """)

        let outcome = try service.ingest(result, originalFile: nil)

        guard case .medicationStart = outcome else { return XCTFail("expected .medicationStart outcome") }
        let meds = try medStore.medications()
        XCTAssertEqual(meds.first?.drugName, "Apoquel")
        XCTAssertEqual(meds.first?.dosage, "16mg")
        XCTAssertNotNil(meds.first?.refillDueAt)
    }

    func testUnsupportedTypeStillSavesFileButWritesNoRecord() throws {
        let result = try decode("""
        {
          "event_type": "weight",
          "occurred_at": "2026-04-01T12:00:00Z",
          "title": "Weight",
          "fields": { "weight_kg": 12.3 }
        }
        """)

        let outcome = try service.ingest(result, originalFile: (Data("img".utf8), "scale.jpg"))

        XCTAssertEqual(outcome, .unsupported(.weight))
        XCTAssertTrue(try vaxStore.vaccinations().isEmpty)
        XCTAssertTrue(try vetVisitStore.visits().isEmpty)
        XCTAssertEqual(try documentStore.read(named: "scale.jpg"), Data("img".utf8))
    }
}
