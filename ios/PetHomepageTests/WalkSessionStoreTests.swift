// ios/PetHomepageTests/WalkSessionStoreTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class WalkSessionStoreTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var walkType: ActivityType!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "walk-tests-\(UUID().uuidString)")
        let petStore = PetStore(context: context, defaults: defaults)
        let activityStore = ActivityStore(context: context, petStore: petStore)
        walkType = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
    }

    private func makeStore(now: Date) -> WalkSessionStore {
        WalkSessionStore(context: context, defaults: defaults, now: { now })
    }

    func testStartEndWritesActivitySpan() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        _ = try store.startActivity(typeID: walkType.id, source: .manual)
        XCTAssertNotNil(store.active)

        let t1 = t0.addingTimeInterval(30 * 60)
        let endStore = makeStore(now: t1) // fresh instance: persistence must carry the session
        let entry = try endStore.end()
        XCTAssertEqual(entry?.performedAt, t0)
        XCTAssertEqual(entry?.endedAt, t1)
        XCTAssertEqual(entry?.kind, .activity)
        XCTAssertNil(endStore.active)
    }

    func testSecondStartThrows() throws {
        let store = makeStore(now: Date())
        _ = try store.startActivity(typeID: walkType.id, source: .manual)
        XCTAssertThrowsError(try store.startActivity(typeID: walkType.id,
                                                     source: .manual)) { error in
            XCTAssertEqual(error as? WalkSessionError, .sessionAlreadyActive)
        }
    }

    func testBackdatedStart() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        let session = try store.startActivity(typeID: walkType.id,
                                              startedAt: t0.addingTimeInterval(-300),
                                              source: .detected)
        XCTAssertEqual(session.startedAt, t0.addingTimeInterval(-300))
        XCTAssertEqual(session.source, .detected)
    }

    func testExpireIfStaleLogsOpenEndedEntry() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try makeStore(now: t0).startActivity(typeID: walkType.id, source: .manual)
        let later = makeStore(now: t0.addingTimeInterval(5 * 60 * 60))
        let entry = try later.expireIfStale()
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.endedAt)
        XCTAssertNil(later.active)
    }

    func testExpireIfStaleKeepsFreshSession() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try makeStore(now: t0).startActivity(typeID: walkType.id, source: .manual)
        let later = makeStore(now: t0.addingTimeInterval(60 * 60))
        XCTAssertNil(try later.expireIfStale())
        XCTAssertNotNil(later.active)
    }

    func testCancelDiscardsWithoutLogging() throws {
        let store = makeStore(now: Date())
        _ = try store.startActivity(typeID: walkType.id, source: .manual)
        store.cancel()
        XCTAssertNil(store.active)
        XCTAssertNil(try store.end())
    }

    func testEndRoutineSessionChecksOffSlot() throws {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Evening walk"
        task.categoryRaw = ActivityCategory.training.rawValue
        task.iconName = "figure.walk"
        task.hour = 17
        task.minute = 30
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date(timeIntervalSince1970: 0)
        task.isOneOff = false
        try context.save()

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try makeStore(now: t0).startRoutine(taskID: task.id, source: .manual)
        let entry = try makeStore(now: t0.addingTimeInterval(1800)).end()
        XCTAssertEqual(entry?.kind, .routine)
        XCTAssertEqual(entry?.performedAt, t0)
        XCTAssertEqual(entry?.durationMinutes, 30)
        XCTAssertEqual(entry?.routineLineageID, task.lineageID)
    }

    func testEndRoutineSessionDedupesExistingCompletion() throws {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Evening walk"
        task.categoryRaw = ActivityCategory.training.rawValue
        task.iconName = "figure.walk"
        task.hour = 17
        task.minute = 30
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date(timeIntervalSince1970: 0)
        task.isOneOff = false
        try context.save()

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let petStore = PetStore(context: context, defaults: defaults)
        let routineStore = RoutineStore(context: context, petStore: petStore, calendar: .current)
        let existing = try routineStore.checkOff(task, on: t0, now: t0)

        _ = try makeStore(now: t0).startRoutine(taskID: task.id, startedAt: t0, source: .manual)
        let entry = try makeStore(now: t0.addingTimeInterval(1800)).end()
        XCTAssertEqual(entry?.objectID, existing.objectID)
        XCTAssertEqual(entry?.durationMinutes, 30)

        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", LogKind.routine.rawValue)
        XCTAssertEqual(try context.fetch(request).count, 1)
    }
}
