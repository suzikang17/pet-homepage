// ios/PetHomepageTests/DueReminderPlannerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

/// The launch resync for vaccination / vet-cadence / activity reminders.
///
/// Before this existed, those three kinds were armed once when a record was saved and never
/// re-derived. A fresh install (or a restore, or a record synced in from another device) left the
/// user with no pending reminders at all and nothing to reveal it — which is what these tests
/// simulate: a store full of data and a scheduler that has never seen any of it.
final class DueReminderPlannerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var logStore: LogStore!
    private var activityStore: ActivityStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        logStore = nil
        activityStore = nil
        calendar = nil
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testResyncArmsAllThreeKindsFromAColdScheduler() async throws {
        _ = try logStore.logVaccine(name: "Rabies", performedAt: date(2026, 1, 1),
                                    nextDueAt: date(2027, 1, 1), lotNumber: nil,
                                    administeredBy: nil)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower",
                                                defaultIntervalDays: 30)
        _ = try logStore.logActivity(type: type, performedAt: date(2026, 8, 1), note: nil,
                                     intervalDays: 30)
        _ = try logStore.logVetVisit(occurredAt: date(2026, 6, 1), clinicName: nil, vetName: nil,
                                     reason: "Checkup", diagnosis: nil, treatmentNotes: nil,
                                     nextVisitDate: nil)

        // A scheduler that has never seen any of this — i.e. straight after a reinstall.
        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake, calendar: calendar,
                                       now: { self.date(2026, 8, 16) })

        await DueReminderPlanner.resync(context: context, using: due, cadenceMonths: 6)

        let vaccinations = await fake.pendingIDs(kind: .vaccination)
        let activities = await fake.pendingIDs(kind: .activity)
        let vet = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(vaccinations.count, 1, "the vaccination's due reminder should be re-armed")
        XCTAssertEqual(activities.count, 1, "the bath's due reminder should be re-armed")
        XCTAssertEqual(vet.count, 1, "the vet cadence reminder should be re-armed")
    }

    /// Activity reminders are keyed by the LOG ENTRY's id, and only the newest log of a type is
    /// live. Re-arming older entries would resurrect reminders for cycles already completed.
    func testResyncArmsOnlyTheNewestLogOfEachActivityType() async throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower",
                                                defaultIntervalDays: 30)
        _ = try logStore.logActivity(type: type, performedAt: date(2026, 5, 1), note: nil,
                                     intervalDays: 30)
        let newest = try logStore.logActivity(type: type, performedAt: date(2026, 8, 1), note: nil,
                                              intervalDays: 30)

        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake, calendar: calendar,
                                       now: { self.date(2026, 8, 16) })

        await DueReminderPlanner.resync(context: context, using: due, cadenceMonths: 6)

        let activities = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(activities, [newest.id],
                       "only the newest log of a type owns the live reminder")
    }

    func testResyncIsIdempotent() async throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower",
                                                defaultIntervalDays: 30)
        _ = try logStore.logActivity(type: type, performedAt: date(2026, 8, 1), note: nil,
                                     intervalDays: 30)
        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake, calendar: calendar,
                                       now: { self.date(2026, 8, 16) })

        await DueReminderPlanner.resync(context: context, using: due, cadenceMonths: 6)
        await DueReminderPlanner.resync(context: context, using: due, cadenceMonths: 6)

        let activities = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(activities.count, 1, "running it every launch must not accumulate duplicates")
    }

    func testResyncWithNoDataSchedulesNothing() async throws {
        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake, calendar: calendar,
                                       now: { self.date(2026, 8, 16) })

        await DueReminderPlanner.resync(context: context, using: due, cadenceMonths: 6)

        let vaccinations = await fake.pendingIDs(kind: .vaccination)
        let activities = await fake.pendingIDs(kind: .activity)
        let vet = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertTrue(vaccinations.isEmpty)
        XCTAssertTrue(activities.isEmpty)
        XCTAssertTrue(vet.isEmpty, "no visits logged means no cadence to remind about")
    }
}
