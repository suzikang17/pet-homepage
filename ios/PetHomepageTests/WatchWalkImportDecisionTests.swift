// ios/PetHomepageTests/WatchWalkImportDecisionTests.swift
import XCTest

@testable import PetHomepage

final class WatchWalkImportDecisionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tuning = WalkDetectionTuning.default // 30 min overlap tolerance

    private func decide(startOffsetMinutes: Double = 60, durationMinutes: Double = 30,
                        importSince: Date? = nil,
                        existing: [LoggedWalkSpan] = [],
                        activeSessionStart: Date? = nil) -> Bool {
        let start = t0.addingTimeInterval(startOffsetMinutes * 60)
        return WatchWalkImportDecision.shouldImport(
            workoutStart: start, workoutEnd: start.addingTimeInterval(durationMinutes * 60),
            importSince: importSince ?? t0,
            existingWalks: existing, activeSessionStart: activeSessionStart, tuning: tuning)
    }

    private func span(startOffsetMinutes: Double, durationMinutes: Double?) -> LoggedWalkSpan {
        let start = t0.addingTimeInterval(startOffsetMinutes * 60)
        return LoggedWalkSpan(
            start: start,
            end: durationMinutes.map { start.addingTimeInterval($0 * 60) })
    }

    func testFreshWorkoutImports() {
        XCTAssertTrue(decide())
    }

    func testTooShortForAWalkSkips() {
        XCTAssertFalse(decide(durationMinutes: 3))
    }

    func testWorkoutBeforeEnableDateSkips() {
        // Workout runs 60–90 min after t0; import enabled at t0+2h.
        XCTAssertFalse(decide(importSince: t0.addingTimeInterval(2 * 60 * 60)))
    }

    func testNilImportSinceRefuses() {
        let start = t0.addingTimeInterval(60 * 60)
        XCTAssertFalse(WatchWalkImportDecision.shouldImport(
            workoutStart: start, workoutEnd: start.addingTimeInterval(30 * 60),
            importSince: nil, existingWalks: [], activeSessionStart: nil, tuning: tuning))
    }

    func testOverlappingLoggedWalkSkips() {
        // Phone detection logged 55–85 min; workout 60–90 min is the same walk.
        XCTAssertFalse(decide(existing: [span(startOffsetMinutes: 55, durationMinutes: 30)]))
    }

    func testWalkWithinToleranceSkips() {
        // A bare check-off (no span) 20 min after the workout ended: same walk, logged by hand.
        XCTAssertFalse(decide(existing: [span(startOffsetMinutes: 110, durationMinutes: nil)]))
    }

    func testDistantWalkDoesNotBlock() {
        // The morning walk ended hours before this workout.
        XCTAssertTrue(decide(existing: [span(startOffsetMinutes: -300, durationMinutes: 30)]))
    }

    func testActiveSessionOverlappingSkips() {
        // A live session that started mid-workout will log this walk itself when it ends.
        XCTAssertFalse(decide(activeSessionStart: t0.addingTimeInterval(70 * 60)))
    }

    func testActiveSessionWellAfterWorkoutImports() {
        // Workout 60–90 min; a new live walk starting 3 h later is a different walk.
        XCTAssertTrue(decide(activeSessionStart: t0.addingTimeInterval(270 * 60)))
    }
}
