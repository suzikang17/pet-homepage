// ios/PetHomepageTests/WalkSlotFinderTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class WalkSlotFinderTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var routineStore: RoutineStore!
    private var calendar: Calendar!
    /// A fixed reference day at 17:00 local time.
    private var five: Date!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "slot-finder-\(UUID().uuidString)")
        calendar = Calendar.current
        let petStore = PetStore(context: context, defaults: defaults)
        _ = try petStore.ensurePet()
        routineStore = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        five = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date())
    }

    private func makeWalkTask(hour: Int, minute: Int, name: String = "Walk") throws -> RoutineTask {
        try routineStore.createTask(name: name, category: .training, iconName: "figure.walk",
                                    hour: hour, minute: minute, weekdayMask: Weekdays.all,
                                    from: calendar.date(byAdding: .day, value: -7, to: five)!)
    }

    func testSlotInsideWindowAttaches() throws {
        let task = try makeWalkTask(hour: 17, minute: 30)
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertEqual(found?.lineageID, task.lineageID)
    }

    func testCompletedSlotIsSkipped() throws {
        let task = try makeWalkTask(hour: 17, minute: 30)
        _ = try routineStore.checkOff(task, on: five, now: five)
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertNil(found)
    }

    func testSlotOutsideWindowIgnored() throws {
        _ = try makeWalkTask(hour: 8, minute: 0)
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertNil(found)
    }

    func testNonWalkSlotIsNeverAttached() throws {
        // An open feeding slot right at the walk time must not be "completed by a walk".
        _ = try routineStore.createTask(name: "Breakfast", category: .feeding,
                                        iconName: "fork.knife", hour: 17, minute: 0,
                                        weekdayMask: Weekdays.all,
                                        from: calendar.date(byAdding: .day, value: -7, to: five)!)
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertNil(found)
    }

    func testWalkNamedSlotAttachesRegardlessOfCategory() throws {
        let task = try routineStore.createTask(name: "Evening walk", category: .other,
                                               iconName: "pawprint", hour: 17, minute: 15,
                                               weekdayMask: Weekdays.all,
                                               from: calendar.date(byAdding: .day, value: -7, to: five)!)
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertEqual(found?.lineageID, task.lineageID)
    }

    func testNearestOfTwoWins() throws {
        _ = try makeWalkTask(hour: 16, minute: 0, name: "Afternoon walk")
        let closer = try makeWalkTask(hour: 17, minute: 15, name: "Evening walk")
        let found = try WalkSlotFinder.openWalkSlot(near: five, withinMinutes: 90,
                                                    context: context, defaults: defaults,
                                                    calendar: calendar)
        XCTAssertEqual(found?.lineageID, closer.lineageID)
    }
}
