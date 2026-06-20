// ios/PetHomepageTests/RecordUploadViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RecordUploadViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var vaxStore: VaccinationStore!
    private var vetVisitStore: VetVisitStore!
    private var medStore: MedicationStore!
    private var documentStore: DocumentStore!
    private var baseURL: URL!
    private var ingestion: RecordIngestionService!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vaxStore = VaccinationStore(context: context, petStore: petStore)
        vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        medStore = MedicationStore(context: context, petStore: petStore)
        baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        documentStore = DocumentStore(baseURL: baseURL)
        ingestion = RecordIngestionService(vaccinationStore: vaxStore, vetVisitStore: vetVisitStore,
                                           medicationStore: medStore, documentStore: documentStore,
                                           calendar: Calendar(identifier: .gregorian))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    private func vaccinationResult() throws -> ExtractionResult {
        try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data("""
        { "event_type": "vaccination", "occurred_at": "2026-03-01T10:00:00Z", "title": "Rabies",
          "fields": { "vaccine_name": "Rabies", "administered_at": "2026-03-01" } }
        """.utf8))
    }

    func testExtractMovesToParsedState() async throws {
        let result = try vaccinationResult()
        let fake = FakeExtractionService(results: [result])
        let vm = RecordUploadViewModel(extractionService: fake, ingestionService: ingestion)

        await vm.extract(fileData: Data("pdf".utf8), fileName: "r.pdf", mimeType: "application/pdf")

        XCTAssertEqual(vm.state, .parsed([result]))
        XCTAssertEqual(fake.lastMimeType, "application/pdf")
    }

    func testConfirmSaveIngestsAndSavesFile() async throws {
        let result = try vaccinationResult()
        let fake = FakeExtractionService(results: [result])
        let vm = RecordUploadViewModel(extractionService: fake, ingestionService: ingestion)
        await vm.extract(fileData: Data("pdf".utf8), fileName: "r.pdf", mimeType: "application/pdf")

        await vm.confirmSave(fileData: Data("pdf".utf8), fileName: "r.pdf")

        if case .saved(let outcomes) = vm.state {
            XCTAssertEqual(outcomes.count, 1)
        } else {
            XCTFail("expected .saved, got \(vm.state)")
        }
        XCTAssertEqual(try vaxStore.vaccinations().count, 1)
        XCTAssertEqual(try documentStore.read(named: "r.pdf"), Data("pdf".utf8))
    }

    func testExtractFailureMovesToFailedState() async throws {
        let fake = FakeExtractionService(results: [], errorToThrow: ExtractionError.badStatus(500))
        let vm = RecordUploadViewModel(extractionService: fake, ingestionService: ingestion)

        await vm.extract(fileData: Data(), fileName: "r.pdf", mimeType: "application/pdf")

        if case .failed = vm.state {} else { XCTFail("expected .failed, got \(vm.state)") }
    }
}
