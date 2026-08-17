// ios/PetHomepageTests/DueReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class DueReminderSchedulerTests: XCTestCase {
    /// These tests use hardcoded due dates. Pin the clock so they assert the same thing forever:
    /// without this they silently changed meaning once real time passed their due dates, and
    /// started exercising the overdue re-nag branch instead of the one-shot branch.
    private static let fixedNow = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!

    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var pet: Pet!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        pet = try petStore.createPet(name: "Sandy", species: "dog")
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        pet = nil
        activityStore = nil
        logStore = nil
        calendar = nil
    }

    func testVaccinationReminderUsesNextDueAtDate() throws {
        let due = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
                                          nextDueAt: due, lotNumber: nil, administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })

        let reminder = sched.vaccinationReminder(for: vax)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .vaccination)
        XCTAssertEqual(reminder?.entityID, vax.id)
        XCTAssertEqual(reminder?.dateComponents?.year, 2027)
        XCTAssertEqual(reminder?.dateComponents?.month, 3)
        XCTAssertEqual(reminder?.dateComponents?.day, 15)
        XCTAssertTrue(reminder?.body.contains("Rabies") ?? false)
        XCTAssertTrue(reminder?.body.contains("Sandy") ?? false, "body should name the pet: \(reminder?.body ?? "")")
    }

    func testVaccinationWithoutNextDueHasNoReminder() throws {
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
                                          nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })
        XCTAssertNil(sched.vaccinationReminder(for: vax))
    }

    func testSyncVaccinationSchedulesAndCancelsWhenDueRemoved() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })
        let due = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
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
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 8, minute: 30, now: { Self.fixedNow })
        let lastVisit = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let reminder = sched.vetCadenceReminder(petID: pet.id, petName: pet.name, lastVisit: lastVisit,
                                                cadence: VetCadence(months: 6, hour: 8, minute: 30))

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .vetCadence)
        XCTAssertEqual(reminder?.entityID, pet.id)
        XCTAssertEqual(reminder?.dateComponents?.year, 2026)
        XCTAssertEqual(reminder?.dateComponents?.month, 7)
        XCTAssertEqual(reminder?.dateComponents?.day, 10)
        XCTAssertEqual(reminder?.hour, 8)
        XCTAssertEqual(reminder?.minute, 30)
        XCTAssertTrue(reminder?.body.contains("Sandy") ?? false, "body should name the pet: \(reminder?.body ?? "")")
    }

    func testSyncVetCadenceSchedulesThenCancels() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30, now: { Self.fixedNow })
        let lastVisit = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        await sched.syncVetCadence(petID: pet.id, petName: pet.name, lastVisit: lastVisit,
                                   cadence: VetCadence(months: 6, hour: 8, minute: 30))
        var pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(pending, [pet.id])

        await sched.cancelVetCadence(petID: pet.id)
        pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSyncVetCadenceWithNoLastVisitDoesNotSchedule() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30, now: { Self.fixedNow })

        await sched.syncVetCadence(petID: pet.id, petName: pet.name, lastVisit: nil,
                                   cadence: VetCadence(months: 6, hour: 8, minute: 30))

        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSyncVetCadenceForTwoPetsYieldsTwoDistinctPendingReminders() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30, now: { Self.fixedNow })
        let otherPet = try petStore.createPet(name: "Bella", species: "cat")
        let lastVisit = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let cadence = VetCadence(months: 6, hour: 8, minute: 30)

        await sched.syncVetCadence(petID: pet.id, petName: pet.name, lastVisit: lastVisit, cadence: cadence)
        await sched.syncVetCadence(petID: otherPet.id, petName: otherPet.name, lastVisit: lastVisit, cadence: cadence)

        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(Set(pending), Set([pet.id, otherPet.id]))
        XCTAssertEqual(pending.count, 2, "each pet's cadence reminder must coexist, not overwrite the other")
    }

    func testActivityReminderUsesNextDueAt() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try logStore.logActivity(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })

        let reminder = sched.activityReminder(for: log)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .activity)
        XCTAssertEqual(reminder?.entityID, log.id)
        XCTAssertEqual(reminder?.dateComponents?.month, 7)
        XCTAssertEqual(reminder?.dateComponents?.day, 1)
        XCTAssertTrue(reminder?.body.contains("Bath") ?? false)
        XCTAssertTrue(reminder?.body.contains("Sandy") ?? false, "body should name the pet: \(reminder?.body ?? "")")
    }

    func testActivityReminderUsesTypeReminderTime() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower",
                                                defaultIntervalDays: 30, reminderHour: 18, reminderMinute: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try logStore.logActivity(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })

        let reminder = sched.activityReminder(for: log)

        XCTAssertEqual(reminder?.hour, 18)
        XCTAssertEqual(reminder?.minute, 30)
    }

    func testActivityReminderDefaultsToNineWhenTypeUsesDefaults() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try logStore.logActivity(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })

        let reminder = sched.activityReminder(for: log)

        XCTAssertEqual(reminder?.hour, 9)
        XCTAssertEqual(reminder?.minute, 0)
    }

    func testActivityWithoutNextDueHasNoReminder() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try logStore.logActivity(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })
        XCTAssertNil(sched.activityReminder(for: log))
    }

    func testSyncActivitySchedulesThenCancelOnRemoval() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0, now: { Self.fixedNow })
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let log = try logStore.logActivity(type: type, performedAt: Date(timeIntervalSince1970: 0), note: nil, intervalDays: 30)

        await sched.syncActivity(log)
        var pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [log.id])

        await sched.cancelActivity(log)
        pending = await fake.pendingIDs(kind: .activity)
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - Overdue re-nag
    //
    // A one-shot trigger on a date that has already passed never fires, so an ignored due date
    // used to go permanently silent — a vaccination three weeks overdue said nothing at all.
    // Overdue items instead get a DAILY REPEATING trigger (dateComponents == nil), which keeps
    // asking until the thing is actually logged; logging replaces it with the next one-shot.

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testOverdueVaccinationRepeatsDailyUntilActedOn() throws {
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: at(2026, 1, 1),
                                          nextDueAt: at(2026, 8, 1), lotNumber: nil,
                                          administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar,
                                         hour: 9, minute: 0, now: { self.at(2026, 8, 22) })

        let reminder = try XCTUnwrap(sched.vaccinationReminder(for: vax))

        XCTAssertNil(reminder.dateComponents,
                     "an overdue reminder must repeat daily, not sit on a date that already passed")
        XCTAssertEqual(reminder.hour, 9)
    }

    func testVaccinationDueTodayIsStillAOneShotOnToday() throws {
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: at(2026, 1, 1),
                                          nextDueAt: at(2026, 8, 22), lotNumber: nil,
                                          administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar,
                                         hour: 9, minute: 0, now: { self.at(2026, 8, 22, 23) })

        let reminder = try XCTUnwrap(sched.vaccinationReminder(for: vax))

        XCTAssertEqual(reminder.dateComponents?.day, 22,
                       "due today is not overdue — day granularity, same as everywhere else")
    }

    func testOverdueActivityRepeatsDaily() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower",
                                                defaultIntervalDays: 30)
        let log = try logStore.logActivity(type: type, performedAt: at(2026, 6, 1), note: nil,
                                           intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar,
                                         hour: 9, minute: 0, now: { self.at(2026, 8, 22) })

        let reminder = try XCTUnwrap(sched.activityReminder(for: log))

        XCTAssertNil(reminder.dateComponents, "an overdue bath should keep asking")
    }

    func testOverdueVetCadenceRepeatsDaily() throws {
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar,
                                         hour: 9, minute: 0, now: { self.at(2026, 8, 22) })

        let reminder = try XCTUnwrap(sched.vetCadenceReminder(
            petID: pet.id, petName: "Sandy", lastVisit: at(2025, 1, 1),
            cadence: VetCadence(months: 6, hour: 9, minute: 0)))

        XCTAssertNil(reminder.dateComponents, "a long-overdue vet visit should keep asking")
    }
}
