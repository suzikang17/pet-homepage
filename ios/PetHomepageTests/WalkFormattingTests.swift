// ios/PetHomepageTests/WalkFormattingTests.swift
import XCTest

@testable import PetHomepage

final class WalkFormattingTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let gmt = TimeZone(identifier: "GMT")!

    private func date(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 12,
                                                  hour: hour, minute: minute))!
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testClosedSpanSameMeridiemDropsFirstSuffix() {
        let label = WalkFormatting.spanLabel(start: date(hour: 17, minute: 10),
                                             end: date(hour: 17, minute: 42),
                                             locale: locale, timeZone: gmt)
        XCTAssertTrue(label.contains("5:10"), label)
        XCTAssertTrue(label.contains("5:42"), label)
        XCTAssertTrue(label.contains("32 min"), label)
        XCTAssertEqual(occurrences(of: "PM", in: label), 1, label)
    }

    func testCrossMeridiemSpanKeepsBothSuffixes() {
        let label = WalkFormatting.spanLabel(start: date(hour: 11, minute: 50),
                                             end: date(hour: 12, minute: 20),
                                             locale: locale, timeZone: gmt)
        XCTAssertTrue(label.contains("AM"), label)
        XCTAssertTrue(label.contains("PM"), label)
        XCTAssertTrue(label.contains("30 min"), label)
    }

    func testOpenSpanIsJustTheStartTime() {
        let label = WalkFormatting.spanLabel(start: date(hour: 17, minute: 10), end: nil,
                                             locale: locale, timeZone: gmt)
        XCTAssertTrue(label.contains("5:10"), label)
        XCTAssertFalse(label.contains("–"), label)
        XCTAssertFalse(label.contains("min"), label)
    }
}
