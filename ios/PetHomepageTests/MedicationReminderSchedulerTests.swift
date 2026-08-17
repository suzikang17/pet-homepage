// ios/PetHomepageTests/MedicationReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class MedicationReminderSchedulerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    /// A medication whose scheduleTime is at the given hour/minute today.
    private func makeMed(hour: Int, minute: Int, ended: Bool = false) throws -> Medication {
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        let scheduleTime = calendar.date(from: comps)!
        let med = try medStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                      scheduleTime: scheduleTime, nextReminderAt: scheduleTime, refillDueAt: nil)
        if ended {
            med.endedAt = Date(timeIntervalSince1970: 0) // far in the past
            try context.save()
        }
        return med
    }

    override func tearDownWithError() throws {
        context = nil
        medStore = nil
        calendar = nil
    }

    func testDailyMedicationUsesRepeatingTrigger() throws {
        let med = try makeMed(hour: 8, minute: 0) // frequency "daily"
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar)
        // Daily → a repeating trigger (nil dateComponents), no specific date.
        XCTAssertNil(scheduler.reminder(for: med).dateComponents)
    }

    func testIntervalMedicationSchedulesOneShotOnNextOccurrence() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)                  // 1970-01-01 00:00 UTC
        let scheduleTime = Date(timeIntervalSince1970: 8 * 3600)    // 08:00
        let med = try medStore.create(drugName: "Heartgard", dosage: "1",
                                      frequency: "Every 3 days",
                                      scheduleTime: scheduleTime, nextReminderAt: start, refillDueAt: nil)
        let fixedNow = Date(timeIntervalSince1970: 10 * 86_400 + 9 * 3600) // day 10, 09:00
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                    calendar: utc, now: { fixedNow })

        let reminder = scheduler.reminder(for: med)
        // Non-daily → a one-shot on the next 3-day boundary at 08:00 (day 12).
        let comps = try XCTUnwrap(reminder.dateComponents)
        XCTAssertEqual(utc.date(from: comps), Date(timeIntervalSince1970: 12 * 86_400 + 8 * 3600))
    }

    // MARK: - Calendar-expressible cadences must self-repeat
    //
    // A one-shot trigger fires exactly once and is then consumed. Since nothing re-arms
    // medication reminders (syncAll has no launch call site), a monthly preventative that
    // schedules a one-shot goes permanently silent after its first fire. Monthly and weekly
    // ARE expressible as repeating UNCalendarNotificationTriggers, so they must use one.

    func testMonthlyMedicationUsesRepeatingDayOfMonthTrigger() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 2026-03-14 09:00 UTC
        let start = utc.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let med = try medStore.create(drugName: "Simparica", dosage: "1 chew",
                                      frequency: "Monthly",
                                      scheduleTime: start, nextReminderAt: start, refillDueAt: nil)
        let fixedNow = utc.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                    calendar: utc, now: { fixedNow })

        let reminder = scheduler.reminder(for: med)

        XCTAssertTrue(reminder.repeats, "monthly must self-repeat, not fire once and die")
        let comps = try XCTUnwrap(reminder.dateComponents)
        XCTAssertEqual(comps.day, 14, "should repeat on the 14th of every month")
        XCTAssertNil(comps.year, "a repeating monthly trigger must not pin a year")
        XCTAssertNil(comps.month, "a repeating monthly trigger must not pin a month")
    }

    func testWeeklyMedicationUsesRepeatingWeekdayTrigger() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 2026-03-14 is a Saturday → weekday 7 in the Gregorian calendar.
        let start = utc.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let med = try medStore.create(drugName: "Apoquel", dosage: "16mg",
                                      frequency: "Weekly",
                                      scheduleTime: start, nextReminderAt: start, refillDueAt: nil)
        let fixedNow = utc.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                    calendar: utc, now: { fixedNow })

        let reminder = scheduler.reminder(for: med)

        XCTAssertTrue(reminder.repeats, "weekly must self-repeat")
        let comps = try XCTUnwrap(reminder.dateComponents)
        XCTAssertEqual(comps.weekday, 7, "should repeat every Saturday")
        XCTAssertNil(comps.day, "a repeating weekly trigger must not pin a day-of-month")
    }

    /// Day-of-month 29–31 doesn't exist in every month, so a repeating trigger would skip
    /// those months entirely. Those fall back to the one-shot + launch-resync path.
    func testMonthlyOnDay31FallsBackToOneShot() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
        let med = try medStore.create(drugName: "Interceptor", dosage: "1",
                                      frequency: "Monthly",
                                      scheduleTime: start, nextReminderAt: start, refillDueAt: nil)
        let fixedNow = utc.date(from: DateComponents(year: 2026, month: 2, day: 2))!
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                    calendar: utc, now: { fixedNow })

        let reminder = scheduler.reminder(for: med)

        XCTAssertFalse(reminder.repeats, "day 31 can't repeat monthly — must stay a dated one-shot")
        let comps = try XCTUnwrap(reminder.dateComponents)
        XCTAssertNotNil(comps.year, "a one-shot must pin a full date")
    }

    /// "Every 3 days" is not expressible as a repeating calendar trigger, so it keeps the
    /// one-shot behaviour and relies on the launch resync to re-arm.
    func testArbitraryIntervalStaysOneShot() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)
        let med = try medStore.create(drugName: "Heartgard", dosage: "1",
                                      frequency: "Every 3 days",
                                      scheduleTime: Date(timeIntervalSince1970: 8 * 3600),
                                      nextReminderAt: start, refillDueAt: nil)
        let scheduler = MedicationReminderScheduler(
            scheduler: FakeNotificationScheduler(), calendar: utc,
            now: { Date(timeIntervalSince1970: 10 * 86_400 + 9 * 3600) })

        XCTAssertFalse(scheduler.reminder(for: med).repeats)
    }

    func testReminderExtractsHourAndMinuteFromScheduleTime() throws {
        let scheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar)
        let med = try makeMed(hour: 18, minute: 30)

        let reminder = scheduler.reminder(for: med)

        XCTAssertEqual(reminder.medicationID, med.id)
        XCTAssertEqual(reminder.hour, 18)
        XCTAssertEqual(reminder.minute, 30)
        XCTAssertTrue(reminder.body.contains("Apoquel"))
    }

    func testSyncSchedulesActiveMedication() async throws {
        let fake = FakeNotificationScheduler()
        let scheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar)
        let med = try makeMed(hour: 9, minute: 0)

        await scheduler.sync(med)

        let pending = await fake.pendingMedicationIDs()
        XCTAssertEqual(pending, [med.id])
    }

    func testSyncCancelsEndedMedication() async throws {
        let fake = FakeNotificationScheduler()
        let scheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar)
        let med = try makeMed(hour: 9, minute: 0)
        await scheduler.sync(med)            // first scheduled
        med.endedAt = Date(timeIntervalSince1970: 0)
        try context.save()

        await scheduler.sync(med)            // now ended → should cancel

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testCancelRemovesReminder() async throws {
        let fake = FakeNotificationScheduler()
        let scheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar)
        let med = try makeMed(hour: 9, minute: 0)
        await scheduler.sync(med)

        await scheduler.cancel(med)

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testCancelAllRemovesAllPendingReminders() async throws {
        let fake = FakeNotificationScheduler()
        let scheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar)
        let med1 = try makeMed(hour: 8, minute: 0)
        let med2 = try makeMed(hour: 9, minute: 0)
        await scheduler.sync(med1)
        await scheduler.sync(med2)

        await scheduler.cancelAll([med1, med2])

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty, "cancelAll should remove all pending reminders")
    }

    func testSyncAllSchedulesActiveAndCancelsEndedMedications() async throws {
        let fake = FakeNotificationScheduler()
        let scheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar)
        let activeMed = try makeMed(hour: 8, minute: 0, ended: false)
        let endedMed = try makeMed(hour: 9, minute: 0, ended: true)
        // Pre-schedule the ended one so we can confirm it gets cancelled.
        await fake.schedule(scheduler.reminder(for: endedMed))

        await scheduler.syncAll([activeMed, endedMed])

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.contains(activeMed.id), "active medication should be scheduled")
        XCTAssertFalse(pending.contains(endedMed.id), "ended medication should be cancelled")
    }
}
