// ios/PetHomepageTests/ExtractionResultTests.swift
import XCTest
@testable import PetHomepage

final class ExtractionResultTests: XCTestCase {
    private func decode(_ json: String) throws -> ExtractionResult {
        try ExtractionResult.decoder
            .decode(ExtractionResult.self, from: Data(json.utf8))
    }

    func testDecodesVaccination() throws {
        let json = """
        {
          "event_type": "vaccination",
          "occurred_at": "2026-03-01T10:00:00Z",
          "title": "Rabies booster",
          "notes": "annual",
          "fields": {
            "vaccine_name": "Rabies",
            "administered_at": "2026-03-01",
            "administered_by": "Dr. Vet",
            "lot_number": "L42",
            "next_due_at": "2027-03-01"
          }
        }
        """
        let result = try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.eventType, .vaccination)
        XCTAssertEqual(result.title, "Rabies booster")
        guard case let .vaccination(fields) = result.fields else {
            return XCTFail("expected .vaccination fields")
        }
        XCTAssertEqual(fields.vaccineName, "Rabies")
        XCTAssertEqual(fields.administeredAt, "2026-03-01")
        XCTAssertEqual(fields.nextDueAt, "2027-03-01")
        XCTAssertEqual(fields.administeredBy, "Dr. Vet")
        XCTAssertEqual(fields.lotNumber, "L42")
    }

    func testDecodesVetVisitWithOptionalsAbsent() throws {
        let json = """
        {
          "event_type": "vet_visit",
          "occurred_at": "2026-02-14T09:30:00Z",
          "title": "Checkup",
          "fields": { "reason": "Annual exam" }
        }
        """
        let result = try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.eventType, .vetVisit)
        XCTAssertNil(result.notes)
        guard case let .vetVisit(fields) = result.fields else {
            return XCTFail("expected .vetVisit fields")
        }
        XCTAssertEqual(fields.reason, "Annual exam")
        XCTAssertNil(fields.clinicName)
        XCTAssertNil(fields.nextVisitDate)
    }

    func testDecodesMedicationStart() throws {
        let json = """
        {
          "event_type": "medication_start",
          "occurred_at": "2026-01-05T00:00:00Z",
          "title": "Started Apoquel",
          "fields": {
            "drug_name": "Apoquel",
            "dosage": "16mg",
            "frequency": "daily",
            "started_at": "2026-01-05",
            "refill_due_at": "2026-02-05"
          }
        }
        """
        let result = try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data(json.utf8))
        guard case let .medicationStart(fields) = result.fields else {
            return XCTFail("expected .medicationStart fields")
        }
        XCTAssertEqual(fields.drugName, "Apoquel")
        XCTAssertEqual(fields.dosage, "16mg")
        XCTAssertEqual(fields.startedAt, "2026-01-05")
    }

    func testDecodesGeneralFallback() throws {
        let json = """
        {
          "event_type": "general",
          "occurred_at": "2026-04-01T12:00:00Z",
          "title": "Note",
          "fields": { "summary": "Misc record" }
        }
        """
        let result = try ExtractionResult.decoder.decode(ExtractionResult.self, from: Data(json.utf8))
        guard case let .general(fields) = result.fields else {
            return XCTFail("expected .general fields")
        }
        XCTAssertEqual(fields.summary, "Misc record")
    }
}
