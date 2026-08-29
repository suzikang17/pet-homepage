// ios/PetHomepageTests/WalkTimeSuggestionTests.swift
import XCTest

@testable import PetHomepage

final class WalkTimeSuggestionTests: XCTestCase {
    private let tuning = WalkDetectionTuning.default // suggest beyond 30 min drift

    private func slot(_ name: String, _ hour: Int, _ minute: Int,
                      id: UUID = UUID()) -> WalkSlotInfo {
        WalkSlotInfo(id: id, name: name, hour: hour, minute: minute)
    }

    func testDriftedSlotGetsASuggestion() {
        let morning = slot("Morning walk", 8, 00)
        let learned = [LearnedWalkTime(hour: 7, minute: 05, sampleCount: 6)]
        let suggestions = WalkTimeSuggestion.suggestions(learned: learned, slots: [morning],
                                                         tuning: tuning)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.slot, morning)
        XCTAssertEqual(suggestions.first?.suggestedHour, 7)
        XCTAssertEqual(suggestions.first?.suggestedMinute, 05)
    }

    func testCloseEnoughSlotIsLeftAlone() {
        let learned = [LearnedWalkTime(hour: 7, minute: 05, sampleCount: 6)]
        XCTAssertTrue(WalkTimeSuggestion.suggestions(
            learned: learned, slots: [slot("Morning walk", 7, 20)], tuning: tuning).isEmpty)
    }

    func testHabitWithoutASameHalfDaySlotSuggestsNothing() {
        // Evening habit, but only a morning slot exists — creating slots isn't this
        // feature's job.
        let learned = [LearnedWalkTime(hour: 17, minute: 30, sampleCount: 6)]
        XCTAssertTrue(WalkTimeSuggestion.suggestions(
            learned: learned, slots: [slot("Morning walk", 7, 00)], tuning: tuning).isEmpty)
    }

    func testNearestSlotIsTheOneSuggested() {
        let early = slot("Early walk", 6, 00)
        let late = slot("Brunch walk", 10, 30)
        let learned = [LearnedWalkTime(hour: 7, minute: 00, sampleCount: 6)]
        let suggestions = WalkTimeSuggestion.suggestions(learned: learned,
                                                         slots: [late, early], tuning: tuning)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.slot, early)
    }

    func testEachHabitPairsWithItsOwnSlot() {
        let morning = slot("Morning walk", 8, 15)
        let evening = slot("Evening walk", 18, 45)
        let learned = [LearnedWalkTime(hour: 7, minute: 00, sampleCount: 6),
                       LearnedWalkTime(hour: 17, minute: 30, sampleCount: 6)]
        let suggestions = WalkTimeSuggestion.suggestions(learned: learned,
                                                         slots: [morning, evening],
                                                         tuning: tuning)
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(Set(suggestions.map(\.slot.name)), ["Morning walk", "Evening walk"])
    }
}
