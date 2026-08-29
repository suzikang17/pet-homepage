// ios/PetHomepageTests/RetroWalkClassifierTests.swift
import XCTest

@testable import PetHomepage

final class RetroWalkClassifierTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tuning = WalkDetectionTuning.default // 4 min sustained, 90 s gap tolerance

    private func sample(_ offset: TimeInterval, walking: Bool) -> MotionSample {
        MotionSample(startDate: t0.addingTimeInterval(offset), isWalking: walking)
    }

    func testContinuousWalkingLongEnough() {
        let samples = [sample(0, walking: true)]
        XCTAssertTrue(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(5 * 60), tuning: tuning))
    }

    func testWalkingUnderThreshold() {
        let samples = [sample(0, walking: true)]
        XCTAssertFalse(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(3 * 60), tuning: tuning))
    }

    func testShortGapIsAbsorbed() {
        // 3 min walking, 60 s stationary (a crossing), 2 min walking: the run spans
        // 6 min wall-clock, so it counts even though pure walking is under 4 min... the
        // live reducer measures wall-clock from run start the same way.
        let samples = [
            sample(0, walking: true),
            sample(3 * 60, walking: false),
            sample(4 * 60, walking: true),
        ]
        XCTAssertTrue(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(6 * 60), tuning: tuning))
    }

    func testLongGapResetsTheRun() {
        // 3 min walking, 5 min in a shop, 3 min walking: neither run reaches 4 min.
        let samples = [
            sample(0, walking: true),
            sample(3 * 60, walking: false),
            sample(8 * 60, walking: true),
        ]
        XCTAssertFalse(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(11 * 60), tuning: tuning))
    }

    func testWalkStartingWithinTheDoorWindowCounts() {
        // A neighbor chat by the door (10 min stationary), then the walk proper — still
        // inside the 15 min start window.
        let samples = [
            sample(0, walking: false),
            sample(10 * 60, walking: true),
        ]
        XCTAssertTrue(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(15 * 60), tuning: tuning))
    }

    func testWalkStartingDeepIntoTheExcursionDoesNotCount() {
        // Drove to a store, walked the aisles for 6 min: sustained walking, but it began
        // half an hour after leaving home — not a dog walk from the door.
        let samples = [
            sample(0, walking: false),
            sample(30 * 60, walking: true),
            sample(36 * 60, walking: false),
        ]
        XCTAssertFalse(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(60 * 60), tuning: tuning))
    }

    func testNoSamples() {
        XCTAssertFalse(RetroWalkClassifier.sustainedWalk(
            in: [], from: t0, until: t0.addingTimeInterval(30 * 60), tuning: tuning))
    }

    func testOnlyNonWalking() {
        let samples = [sample(0, walking: false)]
        XCTAssertFalse(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(30 * 60), tuning: tuning))
    }

    func testUnsortedSamplesAreOrderedFirst() {
        let samples = [
            sample(4 * 60, walking: true),
            sample(0, walking: true),
            sample(3 * 60, walking: false),
        ]
        XCTAssertTrue(RetroWalkClassifier.sustainedWalk(
            in: samples, from: t0, until: t0.addingTimeInterval(8 * 60), tuning: tuning))
    }
}
