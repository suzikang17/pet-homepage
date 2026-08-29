// ios/PetHomepageTests/WalkHabitLearnerTests.swift
import XCTest

@testable import PetHomepage

final class WalkHabitLearnerTests: XCTestCase {
    private let calendar = Calendar.current
    private let tuning = WalkDetectionTuning.default // 4 samples, ±45 min spread

    private func walk(day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                           hour: hour, minute: minute))!
    }

    func testConsistentMorningsBecomeAHabit() {
        let starts = [walk(day: 1, 7, 00), walk(day: 2, 7, 10), walk(day: 3, 7, 05),
                      walk(day: 4, 7, 20)]
        let learned = WalkHabitLearner.learnedTimes(from: starts, calendar: calendar,
                                                    tuning: tuning)
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.hour, 7)
        // Median of 00/05/10/20 → sorted[2] = 10.
        XCTAssertEqual(learned.first?.minute, 10)
        XCTAssertEqual(learned.first?.sampleCount, 4)
    }

    func testTooFewSamplesIsNoHabit() {
        let starts = [walk(day: 1, 7, 00), walk(day: 2, 7, 05), walk(day: 3, 7, 10)]
        XCTAssertTrue(WalkHabitLearner.learnedTimes(from: starts, calendar: calendar,
                                                    tuning: tuning).isEmpty)
    }

    func testScatteredTimesAreNoHabit() {
        // Four morning walks spread across 5 hours: no consistent time to learn.
        let starts = [walk(day: 1, 5, 00), walk(day: 2, 7, 30), walk(day: 3, 9, 00),
                      walk(day: 4, 10, 30)]
        XCTAssertTrue(WalkHabitLearner.learnedTimes(from: starts, calendar: calendar,
                                                    tuning: tuning).isEmpty)
    }

    func testOneOutlierDoesNotBreakTheHabit() {
        // Four tight mornings plus one 10 AM straggler: habit stands, outlier dropped.
        let starts = [walk(day: 1, 7, 00), walk(day: 2, 7, 10), walk(day: 3, 7, 05),
                      walk(day: 4, 7, 15), walk(day: 5, 10, 00)]
        let learned = WalkHabitLearner.learnedTimes(from: starts, calendar: calendar,
                                                    tuning: tuning)
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.hour, 7)
        XCTAssertEqual(learned.first?.sampleCount, 4)
    }

    func testMorningAndEveningLearnSeparately() {
        let starts = [walk(day: 1, 7, 00), walk(day: 2, 7, 10), walk(day: 3, 7, 05),
                      walk(day: 4, 7, 15),
                      walk(day: 1, 17, 30), walk(day: 2, 17, 40), walk(day: 3, 17, 25),
                      walk(day: 4, 17, 35)]
        let learned = WalkHabitLearner.learnedTimes(from: starts, calendar: calendar,
                                                    tuning: tuning)
        XCTAssertEqual(learned.count, 2)
        XCTAssertEqual(learned.map(\.hour).sorted(), [7, 17])
    }

    func testEmptyHistoryLearnsNothing() {
        XCTAssertTrue(WalkHabitLearner.learnedTimes(from: [], calendar: calendar,
                                                    tuning: tuning).isEmpty)
    }

    func testIsNearMatchesWithinWindow() {
        let habit = LearnedWalkTime(hour: 7, minute: 05, sampleCount: 5)
        XCTAssertTrue(WalkHabitLearner.isNear(walk(day: 9, 7, 30), learned: [habit],
                                              windowMinutes: 45, calendar: calendar))
        XCTAssertFalse(WalkHabitLearner.isNear(walk(day: 9, 9, 00), learned: [habit],
                                               windowMinutes: 45, calendar: calendar))
        XCTAssertFalse(WalkHabitLearner.isNear(walk(day: 9, 7, 30), learned: [],
                                               windowMinutes: 45, calendar: calendar))
    }
}
