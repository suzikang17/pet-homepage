// ios/PetHomepageTests/DueReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class DueReminderSchedulerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var vaxStore: VaccinationStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vaxStore = VaccinationStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    func testVaccinationReminderUsesNextDueAtDate() throws {
        let due = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
        let vax = try vaxStore.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1),
                                      nextDueAt: due, lotNumber: nil, administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

        let reminder = sched.vaccinationReminder(for: vax)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .vaccination)
        XCTAssertEqual(reminder?.entityID, vax.id)
        XCTAssertEqual(reminder?.dateComponents?.year, 2027)
        XCTAssertEqual(reminder?.dateComponents?.month, 3)
        XCTAssertEqual(reminder?.dateComponents?.day, 15)
        XCTAssertTrue(reminder?.body.contains("Rabies") ?? false)
    }

    func testVaccinationWithoutNextDueHasNoReminder() throws {
        let vax = try vaxStore.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1),
                                      nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)
        XCTAssertNil(sched.vaccinationReminder(for: vax))
    }

    func testSyncVaccinationSchedulesAndCancelsWhenDueRemoved() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0)
        let due = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
        let vax = try vaxStore.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1),
                                      nextDueAt: due, lotNumber: nil, administeredBy: nil)

        await sched.syncVaccination(vax)
        var pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertEqual(pending, [vax.id])

        vax.nextDueAt = nil
        try context.save()
        await sched.syncVaccination(vax)
        pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertTrue(pending.isEmpty)
    }

    func testVetCadenceReminderIsLastVisitPlusNMonths() throws {
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 8, minute: 30)
        let lastVisit = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let reminder = sched.vetCadenceReminder(lastVisit: lastVisit, cadence: VetCadence(months: 6, hour: 8, minute: 30))

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .vetCadence)
        XCTAssertEqual(reminder?.dateComponents?.year, 2026)
        XCTAssertEqual(reminder?.dateComponents?.month, 7)
        XCTAssertEqual(reminder?.dateComponents?.day, 10)
        XCTAssertEqual(reminder?.hour, 8)
        XCTAssertEqual(reminder?.minute, 30)
    }

    func testSyncVetCadenceSchedulesThenCancels() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30)
        let lastVisit = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        await sched.syncVetCadence(lastVisit: lastVisit, cadence: VetCadence(months: 6, hour: 8, minute: 30))
        var pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(pending.count, 1)

        await sched.cancelVetCadence()
        pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSyncVetCadenceWithNoLastVisitDoesNotSchedule() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30)

        await sched.syncVetCadence(lastVisit: nil, cadence: VetCadence(months: 6, hour: 8, minute: 30))

        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(pending.isEmpty)
    }

    func testActivityReminderUsesNextDueAt() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try logStore.logActivity(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

        let reminder = sched.activityReminder(for: log)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .activity)
        XCTAssertEqual(reminder?.entityID, log.id)
        XCTAssertEqual(reminder?.dateComponents?.month, 7)
        XCTAssertEqual(reminder?.dateComponents?.day, 1)
        XCTAssertTrue(reminder?.body.contains("Bath") ?? false)
    }

    func testActivityWithoutNextDueHasNoReminder() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try logStore.logActivity(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)
        XCTAssertNil(sched.activityReminder(for: log))
    }

    func testSyncActivitySchedulesThenCancelOnRemoval() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let log = try logStore.logActivity(type: type, performedAt: Date(timeIntervalSince1970: 0), note: nil, intervalDays: 30)

        await sched.syncActivity(log)
        var pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [log.id])

        await sched.cancelActivity(log)
        pending = await fake.pendingIDs(kind: .activity)
        XCTAssertTrue(pending.isEmpty)
    }
}
