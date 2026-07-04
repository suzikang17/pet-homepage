// ios/PetHomepageTests/DueReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class DueReminderSchedulerTests: XCTestCase {
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

    func testVaccinationReminderUsesNextDueAtDate() throws {
        let due = calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
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
        XCTAssertTrue(reminder?.body.contains("Sandy") ?? false, "body should name the pet: \(reminder?.body ?? "")")
    }

    func testVaccinationWithoutNextDueHasNoReminder() throws {
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: Date(timeIntervalSince1970: 1),
                                          nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)
        XCTAssertNil(sched.vaccinationReminder(for: vax))
    }

    func testSyncVaccinationSchedulesAndCancelsWhenDueRemoved() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0)
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
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 8, minute: 30)
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
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30)
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
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30)

        await sched.syncVetCadence(petID: pet.id, petName: pet.name, lastVisit: nil,
                                   cadence: VetCadence(months: 6, hour: 8, minute: 30))

        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSyncVetCadenceForTwoPetsYieldsTwoDistinctPendingReminders() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 8, minute: 30)
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
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

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
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

        let reminder = sched.activityReminder(for: log)

        XCTAssertEqual(reminder?.hour, 18)
        XCTAssertEqual(reminder?.minute, 30)
    }

    func testActivityReminderDefaultsToNineWhenTypeUsesDefaults() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try logStore.logActivity(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

        let reminder = sched.activityReminder(for: log)

        XCTAssertEqual(reminder?.hour, 9)
        XCTAssertEqual(reminder?.minute, 0)
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
