// ios/PetHomepageTests/MedicationFrequencyTests.swift
import XCTest
@testable import PetHomepage

final class MedicationFrequencyTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(MedFrequency(interval: 1, unit: .day).label, "Daily")
        XCTAssertEqual(MedFrequency(interval: 1, unit: .week).label, "Weekly")
        XCTAssertEqual(MedFrequency(interval: 1, unit: .month).label, "Monthly")
        XCTAssertEqual(MedFrequency(interval: 3, unit: .day).label, "Every 3 days")
        XCTAssertEqual(MedFrequency(interval: 2, unit: .week).label, "Every 2 weeks")
        XCTAssertEqual(MedFrequency(interval: 6, unit: .month).label, "Every 6 months")
    }

    func testIntervalClampedToAtLeastOne() {
        XCTAssertEqual(MedFrequency(interval: 0, unit: .day).interval, 1)
        XCTAssertEqual(MedFrequency(interval: -4, unit: .week).interval, 1)
    }

    func testCanonicalLabelsRoundTrip() {
        let cases: [MedFrequency] = [
            .init(interval: 1, unit: .day), .init(interval: 3, unit: .day),
            .init(interval: 1, unit: .week), .init(interval: 2, unit: .week),
            .init(interval: 1, unit: .month), .init(interval: 4, unit: .month),
        ]
        for f in cases {
            XCTAssertEqual(MedFrequency(parsing: f.label), f, "round-trip failed for \(f.label)")
        }
    }

    func testParsesLegacyAndFreeText() {
        XCTAssertEqual(MedFrequency(parsing: ""), .init(interval: 1, unit: .day))
        XCTAssertEqual(MedFrequency(parsing: "once a day"), .init(interval: 1, unit: .day))
        XCTAssertEqual(MedFrequency(parsing: "weekly"), .init(interval: 1, unit: .week))
        XCTAssertEqual(MedFrequency(parsing: "every month"), .init(interval: 1, unit: .month))
        XCTAssertEqual(MedFrequency(parsing: "every 5 days"), .init(interval: 5, unit: .day))
        XCTAssertEqual(MedFrequency(parsing: "2 weeks"), .init(interval: 2, unit: .week))
        // Unsupported / unparseable degrades to daily (no crash, sensible default).
        XCTAssertEqual(MedFrequency(parsing: "twice daily"), .init(interval: 1, unit: .day))
        XCTAssertEqual(MedFrequency(parsing: "as needed"), .init(interval: 1, unit: .day))
    }

    func testNextOccurrenceStepsForwardPastNow() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)               // day 0, 00:00
        let time = Date(timeIntervalSince1970: 8 * 3600)         // 08:00
        let now = Date(timeIntervalSince1970: 10 * 86_400 + 9 * 3600) // day 10, 09:00

        // Occurrences at day 0,3,6,9,12 @ 08:00 → first strictly after day-10-09:00 is day 12.
        let next = MedFrequency(interval: 3, unit: .day)
            .nextOccurrence(after: now, start: start, time: time, calendar: utc)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 12 * 86_400 + 8 * 3600))
    }

    func testNextOccurrenceInFutureStartReturnsFirst() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 20 * 86_400)     // starts day 20
        let time = Date(timeIntervalSince1970: 9 * 3600)         // 09:00
        let now = Date(timeIntervalSince1970: 5 * 86_400)        // day 5 (before start)
        let next = MedFrequency(interval: 1, unit: .week)
            .nextOccurrence(after: now, start: start, time: time, calendar: utc)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 20 * 86_400 + 9 * 3600))
    }
}
