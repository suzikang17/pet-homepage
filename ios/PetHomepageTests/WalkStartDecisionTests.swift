// ios/PetHomepageTests/WalkStartDecisionTests.swift
import XCTest

@testable import PetHomepage

final class WalkStartDecisionTests: XCTestCase {
    func testSlotMatchAutoLogsSilentlyWhenOn() {
        let id = UUID()
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: id, resolvedTypeID: UUID(), autoLog: true),
            .silentRoutine(taskID: id))
    }

    func testOffScheduleAutoLogsAgainstResolvedTypeWhenOn() {
        let typeID = UUID()
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: nil, resolvedTypeID: typeID, autoLog: true),
            .silentActivity(typeID: typeID))
    }

    func testNothingToLogAgainstPrompts() {
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: nil, resolvedTypeID: nil, autoLog: true),
            .prompt)
    }

    func testAutoLogOffAlwaysPrompts() {
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: UUID(), resolvedTypeID: UUID(), autoLog: false),
            .prompt)
        XCTAssertEqual(
            WalkStartDecision.mode(matchingSlotTaskID: nil, resolvedTypeID: UUID(), autoLog: false),
            .prompt)
    }

    func testSettingDefaultsOnAndPersists() {
        let store = HomeLocationStore(defaults: UserDefaults(suiteName: "autolog-\(UUID().uuidString)")!)
        XCTAssertTrue(store.autoLog) // default on
        store.autoLog = false
        XCTAssertFalse(store.autoLog)
        store.autoLog = true
        XCTAssertTrue(store.autoLog)
    }
}
