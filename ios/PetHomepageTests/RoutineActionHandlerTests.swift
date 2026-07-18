// ios/PetHomepageTests/RoutineActionHandlerTests.swift
import XCTest
import CoreData
import UserNotifications
@testable import PetHomepage

@MainActor
final class RoutineActionHandlerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private var fake: FakeNotificationScheduler!
    private var handler: RoutineActionHandler!
    private var task: RoutineTask!
    private let calendar = Calendar.current
    /// Fixed clock so snooze math is assertable.
    private let fixedNow = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0,
                                                 of: Date())!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        handler = RoutineActionHandler(context: context, scheduler: fake,
                                       now: { [fixedNow] in fixedNow })
        task = try store.createTask(name: "Morning walk", category: .play,
                                    iconName: "figure.walk", hour: 8, minute: 0,
                                    weekdayMask: Weekdays.all,
                                    from: calendar.date(byAdding: .day, value: -7, to: fixedNow)!)
    }

    private var dailyRequestID: String {
        ReminderIdentifier.requestID(kind: .routine, entityID: task.id)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
        fake = nil
        handler = nil
        task = nil
    }

    func testMarkDoneChecksOffToday() async throws {
        await handler.handle(actionID: RoutineNotificationAction.done, requestID: dailyRequestID)
        let completion = try XCTUnwrap(try store.completion(of: task, on: fixedNow))
        XCTAssertEqual(completion.title, "Morning walk")
        XCTAssertEqual(completion.pet?.name, "Sandy")
    }

    func testMarkDoneFromWeekdaySuffixedRequestParses() async throws {
        // Weekly triggers deliver identifiers like "routine-reminder-<uuid>-w3".
        let weekly = dailyRequestID + "-w3"
        await handler.handle(actionID: RoutineNotificationAction.done, requestID: weekly)
        XCTAssertNotNil(try store.completion(of: task, on: fixedNow))
    }

    func testMarkDoneDedupesAgainstExistingCompletion() async throws {
        try store.checkOff(task, on: fixedNow, now: fixedNow)
        await handler.handle(actionID: RoutineNotificationAction.done, requestID: dailyRequestID)
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", LogKind.routine.rawValue)
        XCTAssertEqual(try context.fetch(request).count, 1) // no double completion
    }

    func testSkipTodayWritesSkipRecord() async throws {
        await handler.handle(actionID: RoutineNotificationAction.skip, requestID: dailyRequestID)
        let slot = try XCTUnwrap(try store.slots(for: fixedNow).first)
        XCTAssertTrue(slot.isSkipped)
    }

    func testSnoozeSchedulesOneShotThirtyMinutesOut() async throws {
        await handler.handle(actionID: RoutineNotificationAction.snooze, requestID: dailyRequestID)
        let reminder = try XCTUnwrap(fake.scheduled.first)
        XCTAssertEqual(reminder.kind, .routineSnooze) // never collides with the repeating trigger
        XCTAssertEqual(reminder.entityID, task.id)
        XCTAssertFalse(reminder.repeats)
        let expected = fixedNow.addingTimeInterval(30 * 60)
        XCTAssertEqual(reminder.dateComponents,
                       calendar.dateComponents([.year, .month, .day], from: expected))
        XCTAssertEqual(reminder.hour, calendar.component(.hour, from: expected))
        XCTAssertEqual(reminder.minute, calendar.component(.minute, from: expected))
        XCTAssertEqual(reminder.body, "Time for Sandy's Morning walk")
    }

    func testSnoozedRequestIdentifierResolvesBackToTheTask() async throws {
        // Acting on the snoozed notification itself (kind routineSnooze) still finds the task.
        let snoozeID = ReminderIdentifier.requestID(kind: .routineSnooze, entityID: task.id)
        await handler.handle(actionID: RoutineNotificationAction.done, requestID: snoozeID)
        XCTAssertNotNil(try store.completion(of: task, on: fixedNow))
    }

    func testNonRoutineAndUnknownRequestsAreIgnored() async throws {
        let medicationID = ReminderIdentifier.requestID(kind: .medication, entityID: task.id)
        await handler.handle(actionID: RoutineNotificationAction.done, requestID: medicationID)
        XCTAssertNil(try store.completion(of: task, on: fixedNow))

        await handler.handle(actionID: RoutineNotificationAction.done, requestID: "garbage")
        XCTAssertNil(try store.completion(of: task, on: fixedNow))

        // A plain tap (default action) opens the app and must not mutate data.
        await handler.handle(actionID: UNNotificationDefaultActionIdentifier,
                             requestID: dailyRequestID)
        XCTAssertNil(try store.completion(of: task, on: fixedNow))
    }
}
