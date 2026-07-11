// ios/PetHomepageTests/RoutineReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineReminderSchedulerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var fake: FakeNotificationScheduler!
    private var scheduler: RoutineReminderScheduler!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        fake = FakeNotificationScheduler()
        scheduler = RoutineReminderScheduler(scheduler: fake)
    }

    private func makeTask(name: String = "Morning walk", mask: Int64 = Weekdays.all,
                          hour: Int = 8, minute: Int = 0, isOneOff: Bool = false,
                          from: Date = Date()) -> RoutineTask {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = .play
        task.iconName = "figure.walk"
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = mask
        task.effectiveFrom = calendar.startOfDay(for: from)
        task.isOneOff = isOneOff
        if isOneOff {
            task.effectiveUntil = calendar.date(byAdding: .day, value: 1, to: task.effectiveFrom)
        }
        return task
    }

    func testAllWeekTaskGetsSingleDailyReminder() {
        let task = makeTask()
        let reminders = scheduler.reminders(for: task, petName: "Bella")
        XCTAssertEqual(reminders.count, 1)
        let reminder = reminders[0]
        XCTAssertEqual(reminder.kind, .routine)
        XCTAssertEqual(reminder.entityID, task.id)
        XCTAssertNil(reminder.dateComponents) // nil = daily repeating trigger
        XCTAssertEqual(reminder.hour, 8)
        XCTAssertEqual(reminder.title, "Morning walk")
        XCTAssertEqual(reminder.body, "Time for Bella's Morning walk")
    }

    func testPartialWeekTaskGetsOneWeeklyReminderPerDay() {
        let task = makeTask(mask: Weekdays.mask(of: [3, 5]), hour: 17)
        let reminders = scheduler.reminders(for: task, petName: nil)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map { $0.dateComponents?.weekday }, [3, 5])
        XCTAssertTrue(reminders.allSatisfy { $0.repeats })
        XCTAssertEqual(reminders[0].body, "Time for Morning walk") // pet-agnostic fallback
    }

    func testFutureOneOffGetsOneShotReminder() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let task = makeTask(name: "Vet pickup", isOneOff: true, from: tomorrow)
        let reminders = scheduler.reminders(for: task, petName: "Bella")
        XCTAssertEqual(reminders.count, 1)
        XCTAssertFalse(reminders[0].repeats) // one-shot on that date
        let expected = calendar.dateComponents([.year, .month, .day],
                                               from: calendar.startOfDay(for: tomorrow))
        XCTAssertEqual(reminders[0].dateComponents, expected)
    }

    func testPastOneOffAndClosedTaskGetNoReminders() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let pastOneOff = makeTask(isOneOff: true, from: yesterday)
        XCTAssertEqual(scheduler.reminders(for: pastOneOff, petName: nil).count, 0)

        let closed = makeTask()
        closed.effectiveUntil = calendar.startOfDay(for: Date())
        XCTAssertEqual(scheduler.reminders(for: closed, petName: nil).count, 0)
    }

    func testSyncTaskReplacesAndCancelClears() async {
        let task = makeTask(mask: Weekdays.mask(of: [2, 4, 6]))
        await scheduler.syncTask(task, petName: "Bella")
        XCTAssertEqual(fake.scheduled.count, 3)
        // Re-sync after narrowing the days: stale weekdays must not survive.
        task.weekdayMask = Weekdays.mask(of: [2])
        await scheduler.syncTask(task, petName: "Bella")
        XCTAssertEqual(fake.scheduled.count, 1)
        XCTAssertEqual(fake.scheduled[0].dateComponents?.weekday, 2)
        await scheduler.cancelTask(task)
        XCTAssertEqual(fake.scheduled.count, 0)
    }

    func testSyncAllResetsTheWholeKind() async {
        let stale = makeTask()
        await scheduler.syncTask(stale, petName: nil)
        let current = makeTask(name: "Dinner", hour: 18)
        await scheduler.syncAll(tasks: [current], petName: "Bella")
        XCTAssertEqual(fake.scheduled.map(\.entityID), [current.id])
    }
}
