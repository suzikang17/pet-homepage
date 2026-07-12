// ios/PetHomepageTests/ScheduleViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ScheduleViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private var logStore: LogStore!
    private var model: ScheduleViewModel!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all, from: weekAgo)
        try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                             hour: 8, minute: 0, weekdayMask: Weekdays.all, from: weekAgo)
        model = ScheduleViewModel(store: store, logStore: logStore)
        model.load()
    }

    func testLoadsTodaySlots() {
        XCTAssertTrue(model.isToday)
        XCTAssertFalse(model.isFuture)
        XCTAssertEqual(model.dayTitle, "Today")
        XCTAssertEqual(model.slots.map(\.task.name), ["Breakfast", "Walk"])
        XCTAssertEqual(model.progress.done, 0)
        XCTAssertEqual(model.progress.total, 2)
    }

    func testDayNavigation() {
        model.goToNextDay()
        XCTAssertFalse(model.isToday)
        XCTAssertTrue(model.isFuture)
        model.goToPreviousDay()
        model.goToPreviousDay()
        XCTAssertEqual(model.dayTitle, "Yesterday")
        model.goToToday()
        XCTAssertTrue(model.isToday)
    }

    func testCheckOffCompletesAndArmsToast() throws {
        let slot = try XCTUnwrap(model.slots.first)
        model.checkOff(slot)
        XCTAssertTrue(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertEqual(model.toastCompletion?.title, "Breakfast")
        XCTAssertEqual(model.progress.done, 1)
        model.dismissToast()
        XCTAssertNil(model.toastCompletion)
    }

    func testCheckOffRefusedOnFutureDay() throws {
        model.goToNextDay()
        let slot = try XCTUnwrap(model.slots.first)
        model.checkOff(slot)
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertNil(model.toastCompletion)
    }

    func testUncheckRemovesCompletion() throws {
        model.checkOff(try XCTUnwrap(model.slots.first))
        model.uncheck(try XCTUnwrap(model.slots.first))
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertNil(model.toastCompletion)
    }

    func testToggleSkipExcludesFromProgress() throws {
        model.toggleSkip(try XCTUnwrap(model.slots.first))
        XCTAssertTrue(try XCTUnwrap(model.slots.first).isSkipped)
        XCTAssertEqual(model.progress.total, 1) // skipped slot out of the denominator
        model.toggleSkip(try XCTUnwrap(model.slots.first))
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isSkipped)
        XCTAssertEqual(model.progress.total, 2)
    }

    func testChangeTimeAppliesToShownDayOnly() throws {
        // Track Breakfast by identity: a time override re-sorts the day (7:00 → 15:30 moves
        // it after Walk), so positional .first would grab the wrong slot.
        func breakfast() throws -> RoutineSlot {
            try XCTUnwrap(model.slots.first { $0.task.name == "Breakfast" })
        }
        model.changeTime(try breakfast(), hour: 15, minute: 30)
        let changed = try breakfast()
        XCTAssertEqual(changed.hour, 15)
        XCTAssertEqual(changed.minute, 30)
        XCTAssertNotNil(changed.timeOverride)
        XCTAssertEqual(model.slots.map(\.task.name), ["Walk", "Breakfast"])
        // Tomorrow keeps the template time.
        model.goToNextDay()
        XCTAssertEqual(try breakfast().hour, 7)
        XCTAssertNil(try breakfast().timeOverride)
        // And clearing restores today.
        model.goToToday()
        model.clearTimeChange(try breakfast())
        XCTAssertEqual(try breakfast().hour, 7)
    }

    func testUpdateCompletionTime() throws {
        model.checkOff(try XCTUnwrap(model.slots.first))
        model.updateCompletionTime(try XCTUnwrap(model.slots.first), hour: 6, minute: 45)
        let completion = try XCTUnwrap(try XCTUnwrap(model.slots.first).completion)
        XCTAssertEqual(calendar.component(.hour, from: completion.performedAt), 6)
        XCTAssertEqual(calendar.component(.minute, from: completion.performedAt), 45)
        XCTAssertTrue(calendar.isDate(completion.performedAt, inSameDayAs: today))
    }

    func testAttachPhoto() throws {
        model.checkOff(try XCTUnwrap(model.slots.first))
        let entry = try XCTUnwrap(model.toastCompletion)
        model.attachPhoto(Data([0x01]), to: entry)
        XCTAssertEqual(entry.photoArray.count, 1)
        XCTAssertNil(model.toastCompletion) // toast served its purpose
    }
}
