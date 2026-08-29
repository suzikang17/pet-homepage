// ios/PetHomepageTests/WalkSessionStoreTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class WalkSessionStoreTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var walkType: ActivityType!
    private var pendingDirectory: URL!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "walk-tests-\(UUID().uuidString)")
        let petStore = PetStore(context: context, defaults: defaults)
        let activityStore = ActivityStore(context: context, petStore: petStore)
        walkType = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        pendingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("walk-pending-\(UUID().uuidString)")
    }

    private func makeStore(now: Date) -> WalkSessionStore {
        WalkSessionStore(context: context, defaults: defaults, now: { now },
                         pending: PendingWalkPhotos(directory: pendingDirectory))
    }

    override func tearDownWithError() throws {
        controller = nil
        context = nil
        defaults = nil
        walkType = nil
        try? FileManager.default.removeItem(at: pendingDirectory)
        pendingDirectory = nil
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

    func testTitleForSessionNamesItsSlotOrActivity() throws {
        let store = makeStore(now: Date())
        let activitySession = try store.startActivity(typeID: walkType.id, source: .manual)
        XCTAssertEqual(store.title(for: activitySession), "Walk")
        store.cancel()

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
        let routineSession = try store.startRoutine(taskID: task.id, source: .manual)
        XCTAssertEqual(store.title(for: routineSession), "Evening walk")
        store.cancel()
    }

    func testEndActivitySessionAttachesToOpenWalkSlot() throws {
        // A detected walk that started as a plain activity session (prompt missed the slot)
        // must still complete a nearby open walk slot when it ends.
        let calendar = Calendar.current
        let petStore = PetStore(context: context, defaults: defaults)
        let routineStore = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let task = try routineStore.createTask(name: "Evening walk", category: .training,
                                               iconName: "figure.walk", hour: 17, minute: 30,
                                               weekdayMask: Weekdays.all, from: weekAgo)

        let start = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
        let end = start.addingTimeInterval(35 * 60)
        _ = try makeStore(now: start).startActivity(typeID: walkType.id, source: .detected)
        let entry = try XCTUnwrap(makeStore(now: end).end(at: end))

        XCTAssertEqual(entry.kind, .routine)
        XCTAssertEqual(entry.routineLineageID, task.lineageID)
        XCTAssertEqual(entry.performedAt, start)
        XCTAssertEqual(entry.endedAt, end)
        XCTAssertNotNil(try routineStore.completion(of: task, on: end))
    }

    func testEndActivitySessionIgnoresFarAwaySlot() throws {
        // Slot at 6:00, walk ends at noon — outside the attach window: stays a plain activity.
        let calendar = Calendar.current
        let petStore = PetStore(context: context, defaults: defaults)
        let routineStore = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        _ = try routineStore.createTask(name: "Morning walk", category: .training,
                                        iconName: "figure.walk", hour: 6, minute: 0,
                                        weekdayMask: Weekdays.all, from: weekAgo)

        let start = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: Date())!
        let end = start.addingTimeInterval(30 * 60)
        _ = try makeStore(now: start).startActivity(typeID: walkType.id, source: .detected)
        let entry = try XCTUnwrap(makeStore(now: end).end(at: end))
        XCTAssertEqual(entry.kind, .activity)
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

    // MARK: - Mid-walk photos

    func testBufferedPhotosAttachOnEnd() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        _ = try store.startActivity(typeID: walkType.id, source: .manual)
        store.attachPhoto(Data([1]))
        store.attachPhoto(Data([2]))
        XCTAssertEqual(store.pendingPhotoCount, 2)

        let entry = try XCTUnwrap(try store.end(at: t0.addingTimeInterval(1800)))
        XCTAssertEqual(Set(entry.photoArray.compactMap(\.imageData)), [Data([1]), Data([2])])
    }

    /// Both paths from session to entry go through writeEntry, so a forgotten walk must not
    /// silently drop the photos taken during it.
    func testBufferedPhotosAttachOnStaleExpiry() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let starting = makeStore(now: t0)
        _ = try starting.startActivity(typeID: walkType.id, source: .manual)
        starting.attachPhoto(Data([9]))

        let later = makeStore(now: t0.addingTimeInterval(WalkSessionStore.maxSessionAge + 60))
        let entry = try XCTUnwrap(try later.expireIfStale())
        XCTAssertEqual(entry.photoArray.compactMap(\.imageData), [Data([9])])
    }

    func testBufferIsClearedAfterAttaching() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        _ = try store.startActivity(typeID: walkType.id, source: .manual)
        store.attachPhoto(Data([1]))
        _ = try store.end(at: t0.addingTimeInterval(600))
        XCTAssertEqual(store.pendingPhotoCount, 0)
    }

    /// A capture that cannot be attached must NOT be deleted alongside the ones that could.
    /// The buffer is the only copy of a mid-walk photo (it lives in Application Support, not
    /// Caches, for exactly this reason), and the drain used to clear the whole folder
    /// unconditionally — so any attachment failure destroyed the photo rather than merely
    /// failing to attach it.
    ///
    /// A directory where a JPEG should be is the one attachment failure reachable without a
    /// throwing LogStore: `Data(contentsOf:)` fails on it, and it survives the drain the same
    /// way a photo whose `addPhoto` threw does.
    func testUnattachableBufferedPhotoSurvivesWhileTheRestAttach() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        let session = try store.startActivity(typeID: walkType.id, source: .manual)
        store.attachPhoto(Data([1]))
        let folder = pendingDirectory.appendingPathComponent(session.id.uuidString,
                                                             isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("000001.jpg"), withIntermediateDirectories: true)

        let entry = try XCTUnwrap(try store.end(at: t0.addingTimeInterval(600)))

        XCTAssertEqual(entry.photoArray.compactMap(\.imageData), [Data([1])],
                       "the readable capture still attaches")
        XCTAssertEqual(PendingWalkPhotos(directory: pendingDirectory)
                        .fileURLs(for: session.id).count, 1,
                       "the capture that could not be attached must survive the drain")
    }

    /// Discarding a walk must discard its photos too, or they leak onto the next session's
    /// entry — a walk you deliberately threw away reappearing as someone else's photos.
    func testCancelDiscardsBufferedPhotos() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        let session = try store.startActivity(typeID: walkType.id, source: .manual)
        store.attachPhoto(Data([1]))
        store.cancel()
        XCTAssertEqual(PendingWalkPhotos(directory: pendingDirectory)
                        .photos(for: session.id).count, 0)
    }
}
