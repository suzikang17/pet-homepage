// ios/PetHomepageTests/DailyShuffleTests.swift
import XCTest

@testable import PetHomepage

final class DailyShuffleTests: XCTestCase {
    private let salt = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let items = ["a", "b", "c", "d", "e"]
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyReturnsNil() {
        XCTAssertNil(DailyShuffle.pick([String](), on: day, salt: salt))
    }

    func testSingleAlwaysReturnsThatElement() {
        XCTAssertEqual(DailyShuffle.pick(["only"], on: day, salt: salt), "only")
    }

    func testSameDayAndSaltIsStable() {
        let first = DailyShuffle.pick(items, on: day, salt: salt)
        let second = DailyShuffle.pick(items, on: day, salt: salt)
        XCTAssertEqual(first, second)
    }

    /// Any time within the same calendar day must give the same pick — a pick that changed
    /// at noon would visibly swap the photo under the user's finger.
    func testStableAcrossTheWholeDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: day)
        let expected = DailyShuffle.pick(items, on: start, salt: salt, calendar: calendar)
        for hour in 1..<24 {
            let later = start.addingTimeInterval(TimeInterval(hour) * 3600)
            XCTAssertEqual(DailyShuffle.pick(items, on: later, salt: salt, calendar: calendar),
                           expected, "hour \(hour) diverged")
        }
    }

    func testPickVariesAcrossDays() {
        var seen = Set<String>()
        for offset in 0..<30 {
            let date = day.addingTimeInterval(TimeInterval(offset) * 86_400)
            if let pick = DailyShuffle.pick(items, on: date, salt: salt) { seen.insert(pick) }
        }
        XCTAssertGreaterThan(seen.count, 1, "the pick never changed over 30 days")
    }

    func testDifferentSaltsDivergeOnTheSameDay() {
        var seen = Set<String>()
        for _ in 0..<50 {
            if let pick = DailyShuffle.pick(items, on: day, salt: UUID()) { seen.insert(pick) }
        }
        XCTAssertGreaterThan(seen.count, 1, "every salt picked the same element")
    }

    /// Locks the mix against a hardcoded value. This is the test that would catch someone
    /// swapping in Swift's Hasher, which is randomly seeded per process and would make the
    /// pick differ across launches — invisible to every other test here, since they all run
    /// inside one process.
    func testMixIsDeterministicAcrossProcesses() {
        XCTAssertEqual(DailyShuffle.index(count: 5, dayNumber: 19_675, salt: salt), 4)
        XCTAssertEqual(DailyShuffle.index(count: 5, dayNumber: 19_676, salt: salt), 2)
        XCTAssertEqual(DailyShuffle.index(count: 5, dayNumber: 19_675, salt: other), 1)
    }
}
