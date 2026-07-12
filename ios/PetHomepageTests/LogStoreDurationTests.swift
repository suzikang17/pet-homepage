// ios/PetHomepageTests/LogStoreDurationTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class LogStoreDurationTests: XCTestCase {
    private var controller: PersistenceController!
    private var logStore: LogStore!
    private var activityStore: ActivityStore!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "log-duration-\(UUID().uuidString)")!)
        logStore = LogStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
    }

    private func makeWalkType() throws -> ActivityType {
        try activityStore.createType(name: "Walk", category: .training,
                                     iconName: "figure.walk", defaultIntervalDays: 0)
    }

    func testLogActivityStoresEndedAt() throws {
        let type = try makeWalkType()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(32 * 60)
        let entry = try logStore.logActivity(type: type, performedAt: start, endedAt: end,
                                             note: nil, intervalDays: 0)
        XCTAssertEqual(entry.endedAt, end)
        XCTAssertEqual(entry.durationMinutes, 32)
    }

    func testLogActivityWithoutEndHasNilDuration() throws {
        let type = try makeWalkType()
        let entry = try logStore.logActivity(type: type, performedAt: Date(), endedAt: nil,
                                             note: nil, intervalDays: 0)
        XCTAssertNil(entry.endedAt)
        XCTAssertNil(entry.durationMinutes)
    }

    func testEndBeforeStartThrows() throws {
        let type = try makeWalkType()
        let start = Date()
        XCTAssertThrowsError(try logStore.logActivity(type: type, performedAt: start,
                                                      endedAt: start.addingTimeInterval(-60),
                                                      note: nil, intervalDays: 0))
    }

    func testUpdateActivityCanSetAndClearEnd() throws {
        let type = try makeWalkType()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = try logStore.logActivity(type: type, performedAt: start, endedAt: nil,
                                             note: nil, intervalDays: 0)
        try logStore.updateActivity(entry, type: type, performedAt: start,
                                    endedAt: start.addingTimeInterval(600), note: nil,
                                    intervalDays: 0)
        XCTAssertEqual(entry.durationMinutes, 10)
        try logStore.updateActivity(entry, type: type, performedAt: start,
                                    endedAt: nil, note: nil, intervalDays: 0)
        XCTAssertNil(entry.endedAt)
    }
}
