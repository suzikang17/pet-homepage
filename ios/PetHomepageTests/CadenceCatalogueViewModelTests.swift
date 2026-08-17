// ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class CadenceCatalogueViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var medStore: MedicationStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 9))!
    }

    private func makeSUT() -> CadenceCatalogueViewModel {
        let fixed = now!
        return CadenceCatalogueViewModel(
            medicationStore: medStore,
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: { fixed }),
            dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()),
            calendar: calendar,
            now: { fixed })
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @discardableResult
    private func makeMed(_ name: String, nextDue: Date, ended: Date? = nil) throws -> Medication {
        let med = try medStore.create(drugName: name, dosage: "1 chew", frequency: "Monthly",
                                      scheduleTime: nextDue, nextReminderAt: nextDue, refillDueAt: nil)
        med.endedAt = ended
        try context.save()
        return med
    }

    @discardableResult
    private func makeType(_ name: String, intervalDays: Int, archived: Bool = false) throws -> ActivityType {
        let type = try activityStore.createType(name: name, category: .care,
                                                iconName: "shower",
                                                defaultIntervalDays: intervalDays)
        if archived { try activityStore.archiveType(type) }
        return type
    }

    func testIncludesBothMedicationsAndActivityTypes() throws {
        try makeMed("Simparica", nextDue: date(9, 14))
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(Set(sut.items.map(\.name)), ["Simparica", "Bath"])
    }

    func testExcludesEndedMedicationsAndArchivedTypes() throws {
        try makeMed("Ended", nextDue: date(9, 14), ended: date(8, 1))
        try makeType("Archived", intervalDays: 30, archived: true)
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Bath"])
    }

    func testExcludesActivityTypesWithNoCadence() throws {
        try makeType("One-off", intervalDays: 0)
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Bath"])
    }

    /// The case the old Upcoming card got wrong: a type that has never been logged has no
    /// LogEntry, so it had no nextDue and never appeared at all.
    func testNeverLoggedActivityTypeStillProducesATile() throws {
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        let bath = try XCTUnwrap(sut.items.first { $0.name == "Bath" })
        XCTAssertNil(bath.lastDone)
        XCTAssertNil(bath.nextDue)
        XCTAssertEqual(bath.dueState(now: now, calendar: calendar), .noCadence)
    }

    /// The other case Upcoming got wrong: its `due >= now` filter hid overdue items entirely.
    func testOverdueItemsAppearAndSortFirst() throws {
        try makeMed("Overdue", nextDue: date(8, 10))     // 6 days ago
        try makeMed("Soon", nextDue: date(8, 20))        // in 4 days
        try makeMed("Today", nextDue: date(8, 16, 17))   // later today
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Overdue", "Today", "Soon"])
    }

    func testNoCadenceItemsSortLast() throws {
        try makeType("Bath", intervalDays: 30)           // never logged -> no cadence
        try makeMed("Soon", nextDue: date(8, 20))
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Soon", "Bath"])
    }

    func testLoggingAMedicationRecordsADoseAndAdvancesIt() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Simparica" })

        await sut.log(item)

        XCTAssertEqual(try logStore.doseCount(for: med), 1)
        let comps = calendar.dateComponents([.month, .day], from: med.nextReminder)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 16)
    }

    func testLoggingAnActivitySetsNextDueFromItsInterval() async throws {
        let type = try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Bath" })

        await sut.log(item)

        let latest = try XCTUnwrap(logStore.latestLog(of: type))
        XCTAssertEqual(latest.performedAt, now)
        let due = try XCTUnwrap(latest.nextDueAt)
        XCTAssertEqual(calendar.dateComponents([.day], from: now, to: due).day, 30)
    }

    /// If the row backing a tile is deleted between `load()` populating `items` and the user
    /// tapping "log" on that now-stale tile, the re-fetch must fail gracefully rather than crash.
    /// `NSManagedObjectContext.object(with:)` never returns nil for a missing row — it hands back
    /// a faulted object whose first property access throws `NSObjectInaccessibleException` — so
    /// this pins `existingObject(with:)`, which does fail with nil for a missing row.
    func testLoggingAMedicationDeletedAfterLoadDoesNotCrashOrRecord() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Simparica" })

        try medStore.delete(med)

        await sut.log(item)

        XCTAssertEqual(try logStore.doseCount(for: med), 0)
    }

    /// A stray tap on a two-column grid is easy; undo has to put things back exactly, including
    /// the cadence the log advanced — otherwise the history looks right while the reminder stays
    /// pushed out for a dose that no longer exists.
    func testUndoRemovesTheDoseAndRollsBackTheCadence() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        let before = med.nextReminder
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Simparica" })

        await sut.log(item)
        XCTAssertEqual(try logStore.doseCount(for: med), 1)
        XCTAssertNotEqual(med.nextReminder, before, "logging should have advanced the cadence")

        await sut.undoLastLog()

        XCTAssertEqual(try logStore.doseCount(for: med), 0, "the dose should be gone")
        XCTAssertEqual(med.nextReminder, before,
                       "with no doses left, the cadence must return to where it started")
    }

    func testUndoAnActivityRestoresThePreviousEntrysReminder() async throws {
        let type = try makeType("Bath", intervalDays: 30)
        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake)
        let fixed = now!
        let sut = CadenceCatalogueViewModel(
            medicationStore: medStore, activityStore: activityStore, logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: fake, calendar: calendar,
                                                           now: { fixed }),
            dueScheduler: due, calendar: calendar, now: { fixed })

        let firstEntry = try logStore.logActivity(type: type, performedAt: date(8, 10), note: nil,
                                                  intervalDays: 30)
        await due.syncActivity(firstEntry)

        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Bath" })
        await sut.log(item)
        await sut.undoLastLog()

        XCTAssertEqual(try logStore.logs(of: type).count, 1, "only the original entry should remain")
        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [firstEntry.id],
                       "undo must re-arm the entry whose reminder the new log displaced")
    }

    func testUndoWithNothingLoggedIsANoOp() async throws {
        try makeMed("Simparica", nextDue: date(8, 16))
        let sut = makeSUT()
        sut.load()

        await sut.undoLastLog()

        XCTAssertEqual(sut.items.count, 1)
    }

    /// DueReminderScheduler keys activity reminders by the LOG ENTRY's id, not the ActivityType's,
    /// so a newly logged entry does NOT replace the previous entry's pending reminder — it has to
    /// be cancelled explicitly, as ActivityLogEditViewModel and CaptureReviewViewModel both do.
    /// Without that, logging a bath mid-cycle leaves the previous cycle's reminder armed and the
    /// user is nagged days after they already did it, accumulating one orphan per mid-cycle tap.
    func testLoggingAnActivityCancelsThePreviousEntrysReminder() async throws {
        let type = try makeType("Bath", intervalDays: 30)
        let fake = FakeNotificationScheduler()
        let due = DueReminderScheduler(scheduler: fake)
        let fixed = now!
        let sut = CadenceCatalogueViewModel(
            medicationStore: medStore, activityStore: activityStore, logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: fake, calendar: calendar,
                                                           now: { fixed }),
            dueScheduler: due, calendar: calendar, now: { fixed })

        // First bath, six days before "now" — arms a reminder keyed to that entry.
        let firstEntry = try logStore.logActivity(type: type, performedAt: date(8, 10), note: nil,
                                                  intervalDays: 30)
        await due.syncActivity(firstEntry)
        let armed = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(armed, [firstEntry.id])

        // Bathe again mid-cycle via a Home tile tap.
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Bath" })
        await sut.log(item)

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertFalse(pending.contains(firstEntry.id),
                       "the superseded entry's reminder must be cancelled, not left armed")
        XCTAssertEqual(pending.count, 1, "exactly one activity reminder should remain")
    }
}
