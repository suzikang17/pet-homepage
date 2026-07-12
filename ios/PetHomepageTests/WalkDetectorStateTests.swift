// ios/PetHomepageTests/WalkDetectorStateTests.swift
import XCTest

@testable import PetHomepage

final class WalkDetectorStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tuning = WalkDetectionTuning.default

    /// Applies an event with defaults suitable for most tests.
    private func apply(_ state: inout WalkDetectorState, _ event: WalkDetectorEvent,
                       rule: WalkPromptRule = .anyWalk, hasActiveSession: Bool = false,
                       isNearScheduledSlot: Bool = false) -> WalkDetectorEffect {
        state.apply(event, rule: rule, hasActiveSession: hasActiveSession,
                    isNearScheduledSlot: isNearScheduledSlot, tuning: tuning)
    }

    /// Walks the clock forward in 30 s samples; returns the first non-.none effect.
    private func sustainedWalk(_ state: inout WalkDetectorState, from start: Date,
                               seconds: TimeInterval, rule: WalkPromptRule = .anyWalk,
                               isNearScheduledSlot: Bool = false) -> WalkDetectorEffect {
        var at = start
        while at.timeIntervalSince(start) <= seconds {
            let effect = apply(&state, .walkingSample(at: at, isWalking: true), rule: rule,
                               isNearScheduledSlot: isNearScheduledSlot)
            if effect != .none { return effect }
            at = at.addingTimeInterval(30)
        }
        return .none
    }

    func testSustainedWalkingPromptsWithBackdatedExit() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        let effect = sustainedWalk(&state, from: t0.addingTimeInterval(30),
                                   seconds: tuning.sustainedWalkSeconds + 60)
        XCTAssertEqual(effect, .promptStart(exitedAt: t0))
    }

    func testSingleNonWalkingGapIsAbsorbed() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        // 2 min walking, one red-light pause, walking resumes: window survives the gap.
        var at = t0.addingTimeInterval(30)
        for _ in 0..<4 {
            XCTAssertEqual(apply(&state, .walkingSample(at: at, isWalking: true)), .none)
            at = at.addingTimeInterval(30)
        }
        XCTAssertEqual(apply(&state, .walkingSample(at: at, isWalking: false)), .none)
        at = at.addingTimeInterval(30)
        let effect = sustainedWalk(&state, from: at, seconds: tuning.sustainedWalkSeconds)
        XCTAssertEqual(effect, .promptStart(exitedAt: t0))
    }

    func testTwoConsecutiveNonWalkingSamplesResetTheWindow() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        var at = t0.addingTimeInterval(30)
        // Almost enough walking...
        for _ in 0..<7 {
            _ = apply(&state, .walkingSample(at: at, isWalking: true))
            at = at.addingTimeInterval(30)
        }
        // ...then a real stop (two samples), which must reset the window.
        _ = apply(&state, .walkingSample(at: at, isWalking: false))
        at = at.addingTimeInterval(30)
        _ = apply(&state, .walkingSample(at: at, isWalking: false))
        at = at.addingTimeInterval(30)
        // Walking resumes: needs the full sustained window again from here.
        let tooSoon = apply(&state, .walkingSample(at: at, isWalking: true))
        XCTAssertEqual(tooSoon, .none)
        let effect = sustainedWalk(&state, from: at.addingTimeInterval(30),
                                   seconds: tuning.sustainedWalkSeconds - 60)
        XCTAssertEqual(effect, .none)
    }

    func testDrivingNeverPrompts() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        var at = t0.addingTimeInterval(30)
        for _ in 0..<40 {
            XCTAssertEqual(apply(&state, .walkingSample(at: at, isWalking: false)), .none)
            at = at.addingTimeInterval(30)
        }
    }

    func testPromptFiresOncePerExcursion() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        let first = sustainedWalk(&state, from: t0.addingTimeInterval(30),
                                  seconds: tuning.sustainedWalkSeconds + 60)
        XCTAssertEqual(first, .promptStart(exitedAt: t0))
        // Keep walking: no second prompt.
        let again = sustainedWalk(&state, from: t0.addingTimeInterval(1000),
                                  seconds: tuning.sustainedWalkSeconds * 2)
        XCTAssertEqual(again, .none)
        // A fresh excursion prompts anew.
        _ = apply(&state, .enteredHome(at: t0.addingTimeInterval(3000)))
        _ = apply(&state, .exitedHome(at: t0.addingTimeInterval(4000)))
        let fresh = sustainedWalk(&state, from: t0.addingTimeInterval(4030),
                                  seconds: tuning.sustainedWalkSeconds + 60)
        XCTAssertEqual(fresh, .promptStart(exitedAt: t0.addingTimeInterval(4000)))
    }

    func testPromptDismissedSuppressesForExcursion() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        _ = apply(&state, .promptDismissed)
        let effect = sustainedWalk(&state, from: t0.addingTimeInterval(30),
                                   seconds: tuning.sustainedWalkSeconds * 2)
        XCTAssertEqual(effect, .none)
    }

    func testRuleOffNeverPrompts() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0), rule: .off)
        let effect = sustainedWalk(&state, from: t0.addingTimeInterval(30),
                                   seconds: tuning.sustainedWalkSeconds * 2, rule: .off)
        XCTAssertEqual(effect, .none)
    }

    func testScheduledOnlyRespectsSlotProximity() {
        var farState = WalkDetectorState.initial
        _ = apply(&farState, .exitedHome(at: t0), rule: .scheduledOnly)
        let far = sustainedWalk(&farState, from: t0.addingTimeInterval(30),
                                seconds: tuning.sustainedWalkSeconds * 2, rule: .scheduledOnly,
                                isNearScheduledSlot: false)
        XCTAssertEqual(far, .none)

        var nearState = WalkDetectorState.initial
        _ = apply(&nearState, .exitedHome(at: t0), rule: .scheduledOnly)
        let near = sustainedWalk(&nearState, from: t0.addingTimeInterval(30),
                                 seconds: tuning.sustainedWalkSeconds + 60, rule: .scheduledOnly,
                                 isNearScheduledSlot: true)
        XCTAssertEqual(near, .promptStart(exitedAt: t0))
    }

    func testNoPromptOverActiveSession() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        var at = t0.addingTimeInterval(30)
        for _ in 0..<20 {
            XCTAssertEqual(apply(&state, .walkingSample(at: at, isWalking: true),
                                 hasActiveSession: true), .none)
            at = at.addingTimeInterval(30)
        }
    }

    func testEnteredHomeEndsActiveSession() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        let entry = t0.addingTimeInterval(2000)
        XCTAssertEqual(apply(&state, .enteredHome(at: entry), hasActiveSession: true),
                       .endSession(at: entry))
    }

    func testEnteredHomeWithoutSessionIsQuietAndResets() {
        var state = WalkDetectorState.initial
        _ = apply(&state, .exitedHome(at: t0))
        XCTAssertEqual(apply(&state, .enteredHome(at: t0.addingTimeInterval(600))), .none)
        XCTAssertEqual(state, .initial)
        // Samples with no excursion in progress do nothing.
        XCTAssertEqual(apply(&state, .walkingSample(at: t0.addingTimeInterval(700),
                                                    isWalking: true)), .none)
    }
}
