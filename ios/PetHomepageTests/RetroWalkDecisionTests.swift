// ios/PetHomepageTests/RetroWalkDecisionTests.swift
import XCTest

@testable import PetHomepage

final class RetroWalkDecisionTests: XCTestCase {
    private let exit = Date(timeIntervalSince1970: 1_700_000_000)
    private let tuning = WalkDetectionTuning.default

    private func decide(awayMinutes: Double = 30, hadActiveSession: Bool = false,
                        promptDismissed: Bool = false, rule: WalkPromptRule = .anyWalk,
                        nearSlot: Bool = false) -> Bool {
        RetroWalkDecision.shouldEvaluate(
            exitedAt: exit, enteredAt: exit.addingTimeInterval(awayMinutes * 60),
            hadActiveSession: hadActiveSession, promptDismissed: promptDismissed,
            rule: rule, isNearScheduledSlot: nearSlot, tuning: tuning)
    }

    func testTypicalExcursionIsEligible() {
        XCTAssertTrue(decide())
    }

    func testActiveSessionSkips() {
        // The live path already captured this excursion.
        XCTAssertFalse(decide(hadActiveSession: true))
    }

    func testNotNowSkips() {
        XCTAssertFalse(decide(promptDismissed: true))
    }

    func testRuleOffSkips() {
        XCTAssertFalse(decide(rule: .off))
    }

    func testScheduledOnlyNeedsANearbySlot() {
        XCTAssertFalse(decide(rule: .scheduledOnly, nearSlot: false))
        XCTAssertTrue(decide(rule: .scheduledOnly, nearSlot: true))
    }

    func testExcursionShorterThanASustainedWalkSkips() {
        XCTAssertFalse(decide(awayMinutes: 3))
    }

    func testAllDayAbsenceSkips() {
        XCTAssertFalse(decide(awayMinutes: 8 * 60))
    }

    func testBoundaryDurationsAreEligible() {
        XCTAssertTrue(decide(awayMinutes: tuning.sustainedWalkSeconds / 60))
        XCTAssertTrue(decide(awayMinutes: tuning.maxRetroExcursionSeconds / 60))
    }
}
