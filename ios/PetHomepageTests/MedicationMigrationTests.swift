// ios/PetHomepageTests/MedicationMigrationTests.swift
import XCTest
import CoreData
@testable import PetHomepage

/// v1 → v2: `startedAt` never meant what its name said — it held the next reminder date, and
/// every dose log overwrote it. v2 adds the honestly-named `nextReminderAt` and carries the
/// values across. Both fields exist because CloudKit's schema is append-only: the old one can be
/// abandoned but never removed.
final class MedicationMigrationTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: MedicationStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = MedicationStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
        calendar = nil
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    /// Simulates a row written by the v1 build: `startedAt` set, `nextReminderAt` still nil.
    private func makeLegacyMedication(startedAt: Date) throws -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.drugName = "Simparica"
        med.dosage = "1 chew"
        med.frequency = "Monthly"
        med.scheduleTime = startedAt
        med.startedAt = startedAt
        med.nextReminderAt = nil
        med.pet = try PetStore(context: context).currentPet()
        try context.save()
        return med
    }

    func testBackfillCopiesLegacyStartedAtIntoNextReminderAt() throws {
        let legacy = try makeLegacyMedication(startedAt: date(2026, 9, 14))

        let migrated = PersistenceController.backfillNextReminderAt(in: context)

        XCTAssertEqual(migrated, 1)
        XCTAssertEqual(legacy.nextReminderAt, date(2026, 9, 14))
        XCTAssertEqual(legacy.nextReminder, date(2026, 9, 14))
    }

    func testBackfillIsIdempotentAndLeavesMigratedRowsAlone() throws {
        let legacy = try makeLegacyMedication(startedAt: date(2026, 9, 14))
        PersistenceController.backfillNextReminderAt(in: context)

        // A dose is logged after migrating, moving the cadence on.
        legacy.nextReminder = date(2026, 10, 14)
        try context.save()

        let secondPass = PersistenceController.backfillNextReminderAt(in: context)

        XCTAssertEqual(secondPass, 0, "a second run must find nothing to do")
        XCTAssertEqual(legacy.nextReminderAt, date(2026, 10, 14),
                       "re-running must not clobber a value written since the migration")
    }

    /// Keyed on `nextReminderAt == nil` rather than a run-once flag, precisely so a record that
    /// arrives later from a device still running the v1 build still gets carried across.
    func testBackfillPicksUpLegacyRowsThatArriveAfterTheFirstRun() throws {
        PersistenceController.backfillNextReminderAt(in: context)

        let lateArrival = try makeLegacyMedication(startedAt: date(2026, 11, 1))
        let secondPass = PersistenceController.backfillNextReminderAt(in: context)

        XCTAssertEqual(secondPass, 1)
        XCTAssertEqual(lateArrival.nextReminderAt, date(2026, 11, 1))
    }

    /// The accessor must never report "no reminder" for an un-migrated row, or a medication would
    /// silently drop off the Home grid and out of the reminder scheduler.
    func testNextReminderFallsBackToLegacyFieldBeforeMigration() throws {
        let legacy = try makeLegacyMedication(startedAt: date(2026, 9, 14))

        XCTAssertNil(legacy.nextReminderAt, "precondition: not yet migrated")
        XCTAssertEqual(legacy.nextReminder, date(2026, 9, 14),
                       "reads must fall through to startedAt until the backfill runs")
    }

    /// New rows never touch the legacy field, so nothing keeps writing the name that lies.
    func testNewMedicationsWriteOnlyTheNewField() throws {
        let med = try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                   scheduleTime: date(2026, 9, 1),
                                   nextReminderAt: date(2026, 9, 14), refillDueAt: nil)

        XCTAssertEqual(med.nextReminderAt, date(2026, 9, 14))
        XCTAssertEqual(med.nextReminder, date(2026, 9, 14))
    }
}
