// ios/PetHomepageTests/WalkActionHandlerTests.swift
import CoreData
import XCTest

@testable import PetHomepage

@MainActor
final class WalkActionHandlerTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var sessions: WalkSessionStore!
    private var handler: WalkActionHandler!
    private var logStore: LogStore!
    private var walkType: ActivityType!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "walk-action-tests-\(UUID().uuidString)")
        let petStore = PetStore(context: context, defaults: defaults)
        logStore = LogStore(context: context, petStore: petStore)
        let activityStore = ActivityStore(context: context, petStore: petStore)
        walkType = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        sessions = WalkSessionStore(context: context, defaults: defaults,
                                    now: { self.start.addingTimeInterval(1800) })
        handler = WalkActionHandler(sessions: sessions, context: context, defaults: defaults,
                                    now: { self.start.addingTimeInterval(1800) })
    }

    func testStartActionCreatesBackdatedSession() throws {
        let requestID = WalkRequestID.detectedActivity(typeID: walkType.id, exitedAt: start).string
        handler.handle(actionID: WalkNotificationAction.start, requestID: requestID)
        let session = try XCTUnwrap(sessions.active)
        XCTAssertEqual(session.startedAt.timeIntervalSince1970,
                       start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.source, .detected)
    }

    func testStartActionIsNoOpWhenSessionActive() throws {
        _ = try sessions.startActivity(typeID: walkType.id, startedAt: start, source: .manual)
        let existing = sessions.active
        let requestID = WalkRequestID.detectedActivity(typeID: walkType.id,
                                                       exitedAt: start.addingTimeInterval(60)).string
        handler.handle(actionID: WalkNotificationAction.start, requestID: requestID)
        XCTAssertEqual(sessions.active, existing)
    }

    func testDismissSetsSuppressionFlag() throws {
        let requestID = WalkRequestID.detectedActivity(typeID: walkType.id, exitedAt: start).string
        handler.handle(actionID: WalkNotificationAction.dismiss, requestID: requestID)
        XCTAssertTrue(defaults.bool(forKey: WalkNotificationAction.dismissedFlagKey))
    }

    func testUndoRestoresSessionAndDeletesEntry() throws {
        _ = try sessions.startActivity(typeID: walkType.id, startedAt: start, source: .detected)
        let entry = try XCTUnwrap(sessions.end(at: start.addingTimeInterval(1800)))
        let requestID = WalkRequestID.ended(entryID: entry.id, startedAt: start).string

        handler.handle(actionID: WalkNotificationAction.undo, requestID: requestID)
        let reopened = try XCTUnwrap(sessions.active)
        XCTAssertEqual(reopened.startedAt.timeIntervalSince1970,
                       start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try logStore.fetch(NSPredicate(value: true)).count, 0)
    }

    func testMalformedRequestIDIsIgnored() throws {
        handler.handle(actionID: WalkNotificationAction.start, requestID: "walk-detected-a-nonsense-99")
        handler.handle(actionID: WalkNotificationAction.undo, requestID: "walk-ended-garbage")
        handler.handle(actionID: WalkNotificationAction.start, requestID: "routine-reminder-nope")
        XCTAssertNil(sessions.active)
    }

    func testRequestIDRoundTrip() throws {
        let a = WalkRequestID.detectedActivity(typeID: walkType.id, exitedAt: start)
        guard case let .detectedActivity(typeID, exitedAt)? = WalkRequestID.parse(a.string) else {
            return XCTFail("failed to parse \(a.string)")
        }
        XCTAssertEqual(typeID, walkType.id)
        XCTAssertEqual(exitedAt.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)

        let taskID = UUID()
        let r = WalkRequestID.detectedRoutine(taskID: taskID, exitedAt: start)
        guard case let .detectedRoutine(parsedTask, _)? = WalkRequestID.parse(r.string) else {
            return XCTFail("failed to parse \(r.string)")
        }
        XCTAssertEqual(parsedTask, taskID)

        let entryID = UUID()
        let e = WalkRequestID.ended(entryID: entryID, startedAt: start)
        guard case let .ended(parsedEntry, parsedStart)? = WalkRequestID.parse(e.string) else {
            return XCTFail("failed to parse \(e.string)")
        }
        XCTAssertEqual(parsedEntry, entryID)
        XCTAssertEqual(parsedStart.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
    }
}
