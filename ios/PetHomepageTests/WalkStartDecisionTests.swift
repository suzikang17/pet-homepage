// ios/PetHomepageTests/WalkStartDecisionTests.swift
import XCTest

@testable import PetHomepage

final class WalkStartDecisionTests: XCTestCase {
    func testScheduledMatchAutoStartsWhenEnabled() {
        let id = UUID()
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: id, autoStartScheduled: true),
            .silentRoutine(taskID: id))
    }

    func testScheduledMatchPromptsWhenDisabled() {
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: UUID(), autoStartScheduled: false),
            .prompt)
    }

    func testNoSlotAlwaysPrompts() {
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: nil, autoStartScheduled: true),
            .prompt)
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: nil, autoStartScheduled: false),
            .prompt)
    }

    func testSettingDefaultsOnAndPersists() {
        let store = HomeLocationStore(defaults: UserDefaults(suiteName: "autostart-\(UUID().uuidString)")!)
        XCTAssertTrue(store.autoStartScheduled) // default on
        store.autoStartScheduled = false
        XCTAssertFalse(store.autoStartScheduled)
        store.autoStartScheduled = true
        XCTAssertTrue(store.autoStartScheduled)
    }
}
