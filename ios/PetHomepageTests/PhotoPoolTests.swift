// ios/PetHomepageTests/PhotoPoolTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class PhotoPoolTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var petStore: PetStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var routineStore: RoutineStore!
    private var pool: PhotoPool!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "photopool-tests-\(UUID().uuidString)")!
        petStore = PetStore(context: context, defaults: defaults)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        routineStore = RoutineStore(context: context, petStore: petStore)
        pool = PhotoPool(context: context, home: HomeLocationStore(defaults: defaults))
    }

    override func tearDownWithError() throws {
        controller = nil; context = nil; defaults = nil
        petStore = nil; activityStore = nil; logStore = nil; routineStore = nil; pool = nil
    }

    private func jpeg(_ byte: UInt8) -> Data { Data([byte]) }

    func testActivityTypePoolIsIsolated() throws {
        let bath = try activityStore.createType(name: "Bath", category: .care,
                                                iconName: "shower", defaultIntervalDays: 30)
        let nails = try activityStore.createType(name: "Nail trim", category: .care,
                                                 iconName: "scissors", defaultIntervalDays: 21)
        let bathLog = try logStore.logActivity(type: bath, performedAt: Date(), note: nil, intervalDays: 30)
        let nailLog = try logStore.logActivity(type: nails, performedAt: Date(), note: nil, intervalDays: 21)
        _ = try logStore.addPhoto(to: bathLog, imageData: jpeg(1))
        _ = try logStore.addPhoto(to: nailLog, imageData: jpeg(2))

        let bathPhotos = try pool.photos(for: .activityType(bath))
        XCTAssertEqual(bathPhotos.count, 1)
        XCTAssertEqual(bathPhotos.first?.imageData, jpeg(1))
    }

    func testEmptyPoolReturnsEmpty() throws {
        let bath = try activityStore.createType(name: "Bath", category: .care,
                                                iconName: "shower", defaultIntervalDays: 30)
        XCTAssertEqual(try pool.photos(for: .activityType(bath)).count, 0)
    }

    func testNewestFirst() throws {
        let bath = try activityStore.createType(name: "Bath", category: .care,
                                                iconName: "shower", defaultIntervalDays: 30)
        let log = try logStore.logActivity(type: bath, performedAt: Date(), note: nil, intervalDays: 30)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try logStore.addPhoto(to: log, imageData: jpeg(1), createdAt: t0)
        _ = try logStore.addPhoto(to: log, imageData: jpeg(2), createdAt: t0.addingTimeInterval(60))

        let photos = try pool.photos(for: .activityType(bath))
        XCTAssertEqual(photos.map(\.imageData), [jpeg(2), jpeg(1)])
    }

    /// The point of this type: a walk logged as a routine completion and a walk logged as an
    /// auto-detected activity land in different pools, and the walk subject must see both.
    func testWalkRoutineTaskUnionsLineageAndActivityTypePools() throws {
        let walkType = try activityStore.createType(name: "Walk", category: .training,
                                                    iconName: "figure.walk", defaultIntervalDays: 0)
        let task = try routineStore.createTask(name: "Morning walk", category: .play,
                                               iconName: "figure.walk", hour: 8, minute: 0,
                                               weekdayMask: Weekdays.all, isWalk: true)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let completion = try routineStore.checkOff(task, on: day, now: day)
        _ = try logStore.addPhoto(to: completion, imageData: jpeg(1))

        let detected = try logStore.logActivity(type: walkType, performedAt: day, note: nil, intervalDays: 0)
        _ = try logStore.addPhoto(to: detected, imageData: jpeg(2))

        let photos = try pool.photos(for: .routineTask(task))
        XCTAssertEqual(Set(photos.compactMap(\.imageData)), [jpeg(1), jpeg(2)])
    }

    /// A non-walk routine task must NOT absorb the Walk activity type's photos.
    func testNonWalkRoutineTaskSeesOnlyItsLineage() throws {
        let walkType = try activityStore.createType(name: "Walk", category: .training,
                                                    iconName: "figure.walk", defaultIntervalDays: 0)
        let task = try routineStore.createTask(name: "Breakfast", category: .feeding,
                                               iconName: "bowl.fill", hour: 7, minute: 0,
                                               weekdayMask: Weekdays.all, isWalk: false)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let completion = try routineStore.checkOff(task, on: day, now: day)
        _ = try logStore.addPhoto(to: completion, imageData: jpeg(1))

        let detected = try logStore.logActivity(type: walkType, performedAt: day, note: nil, intervalDays: 0)
        _ = try logStore.addPhoto(to: detected, imageData: jpeg(2))

        let photos = try pool.photos(for: .routineTask(task))
        XCTAssertEqual(photos.compactMap(\.imageData), [jpeg(1)])
    }
}
