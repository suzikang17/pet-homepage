// ios/PetHomepageTests/RoutineReminderSchedulerTests.swift
import CoreData
import XCTest

@testable import PetHomepage

/// Occurrence-model tests: reminders are one-shots derived from day state, so completing,
/// skipping, or time-shifting a day silences or moves that day's reminder.
final class RoutineReminderSchedulerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var fake: FakeNotificationScheduler!
    private var scheduler: RoutineReminderScheduler!
    private var store: RoutineStore!
    private let calendar = Calendar.current
    /// A fixed "now" at 00:05 today — every occurrence in the horizon is still ahead.
    private var earlyToday: Date!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "reminder-\(UUID().uuidString)")!)
        _ = try petStore.ensurePet()
        store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        fake = FakeNotificationScheduler()
        scheduler = RoutineReminderScheduler(scheduler: fake, calendar: calendar)
        earlyToday = calendar.date(bySettingHour: 0, minute: 5, second: 0,
                                   of: calendar.startOfDay(for: Date()))
    }

    @discardableResult
    private func makeTask(name: String = "Morning walk", hour: Int = 8,
                          minute: Int = 0) throws -> RoutineTask {
        try store.createTask(name: name, category: .play, iconName: "figure.walk",
                             hour: hour, minute: minute, weekdayMask: Weekdays.all,
                             from: calendar.date(byAdding: .day, value: -7, to: earlyToday)!)
    }

    private func occurrences() throws -> [RoutineReminderOccurrence] {
        try RoutineReminderPlanner.occurrences(store: store, calendar: calendar, now: earlyToday)
    }

    override func tearDownWithError() throws {
        context = nil
        fake = nil
        scheduler = nil
        store = nil
        earlyToday = nil
    }

    func testDailyTaskGetsOneOneShotPerHorizonDay() async throws {
        let task = try makeTask()
        let planned = try occurrences()
        XCTAssertEqual(planned.count, RoutineReminderPlanner.horizonDays)
        XCTAssertTrue(planned.allSatisfy { $0.task.id == task.id && $0.hour == 8 })

        await scheduler.syncAll(occurrences: planned, petName: "Sandy")
        XCTAssertEqual(fake.scheduled.count, RoutineReminderPlanner.horizonDays)
        XCTAssertTrue(fake.scheduled.allSatisfy { !$0.repeats && $0.dateComponents?.day != nil })
        XCTAssertEqual(fake.scheduled[0].body, "Time for Sandy's Morning walk")
    }

    func testCompletedTodaySilencesTodayOnly() throws {
        let task = try makeTask()
        _ = try store.checkOff(task, on: earlyToday, now: earlyToday)
        let planned = try occurrences()
        XCTAssertEqual(planned.count, RoutineReminderPlanner.horizonDays - 1)
        XCTAssertFalse(planned.contains { calendar.isDate($0.day, inSameDayAs: earlyToday) })
    }

    func testSkippedTodaySilencesTodayOnly() throws {
        let task = try makeTask()
        try store.skip(task, on: earlyToday)
        let planned = try occurrences()
        XCTAssertEqual(planned.count, RoutineReminderPlanner.horizonDays - 1)
        XCTAssertFalse(planned.contains { calendar.isDate($0.day, inSameDayAs: earlyToday) })
    }

    func testPerDayOverrideMovesTodaysReminderTime() throws {
        let task = try makeTask(hour: 8)
        try store.overrideTime(task, on: earlyToday, hour: 15, minute: 30)
        let planned = try occurrences()
        let today = try XCTUnwrap(planned.first { calendar.isDate($0.day, inSameDayAs: earlyToday) })
        XCTAssertEqual(today.hour, 15)
        XCTAssertEqual(today.minute, 30)
        // Tomorrow keeps the template time.
        let tomorrow = try XCTUnwrap(planned.first {
            calendar.isDate($0.day, inSameDayAs: calendar.date(byAdding: .day, value: 1,
                                                               to: earlyToday)!)
        })
        XCTAssertEqual(tomorrow.hour, 8)
    }

    func testPastTimeTodayIsDropped() throws {
        try makeTask(hour: 8)
        let nineAM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: earlyToday)!
        let planned = try RoutineReminderPlanner.occurrences(store: store, calendar: calendar,
                                                             now: nineAM)
        XCTAssertEqual(planned.count, RoutineReminderPlanner.horizonDays - 1)
        XCTAssertFalse(planned.contains { calendar.isDate($0.day, inSameDayAs: nineAM) })
    }

    func testSyncAllReplacesRoutineKindButKeepsSnoozes() async throws {
        let task = try makeTask()
        // A pending snoozed re-fire must survive routine re-syncs.
        await fake.schedule(PendingReminder(kind: .routineSnooze, entityID: task.id,
                                            title: "t", body: "b", hour: 9, minute: 0,
                                            dateComponents: DateComponents(year: 2026, month: 7, day: 13),
                                            repeats: false))
        await scheduler.syncAll(occurrences: try occurrences(), petName: nil)
        XCTAssertEqual(fake.scheduled.filter { $0.kind == .routine }.count,
                       RoutineReminderPlanner.horizonDays)
        await scheduler.syncAll(occurrences: [], petName: nil)
        XCTAssertEqual(fake.scheduled.filter { $0.kind == .routine }.count, 0)
        XCTAssertEqual(fake.scheduled.filter { $0.kind == .routineSnooze }.count, 1)
    }

    func testCancelTaskClearsOccurrencesAndSnooze() async throws {
        let task = try makeTask()
        await scheduler.syncAll(occurrences: try occurrences(), petName: nil)
        await fake.schedule(PendingReminder(kind: .routineSnooze, entityID: task.id,
                                            title: "t", body: "b", hour: 9, minute: 0))
        await scheduler.cancelTask(task)
        XCTAssertTrue(fake.scheduled.isEmpty)
    }
}
