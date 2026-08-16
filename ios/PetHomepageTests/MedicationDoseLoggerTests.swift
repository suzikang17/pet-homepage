// ios/PetHomepageTests/MedicationDoseLoggerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class MedicationDoseLoggerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!
    private var logStore: LogStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    private func monthlyMed() throws -> Medication {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        return try medStore.create(drugName: "Simparica", dosage: "1 chew", frequency: "Monthly",
                                   scheduleTime: start, startedAt: start, refillDueAt: nil)
    }

    private func logger(now: @escaping () -> Date) -> MedicationDoseLogger {
        MedicationDoseLogger(
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: now),
            calendar: calendar,
            now: now)
    }

    func testLogRecordsDoseAndAdvancesCadenceByOneInterval() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!

        let next = await logger(now: { now }).log(med)

        XCTAssertEqual(try logStore.doseCount(for: med), 1)
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(next))
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 14)
        XCTAssertEqual(comps.hour, 9, "next due keeps the medication's scheduled time of day")
        XCTAssertEqual(med.startedAt, next, "startedAt IS the next-reminder date in this model")
    }

    func testSecondLogOnSameDayIsDeduped() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let sut = logger(now: { now })

        _ = await sut.log(med)
        let second = await sut.log(med)

        XCTAssertNil(second, "a same-day repeat returns nil rather than logging again")
        XCTAssertEqual(try logStore.doseCount(for: med), 1)
    }

    func testExplicitDateBackdatesTheDose() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 9))!
        let backdated = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 8))!

        let next = await logger(now: { now }).log(med, at: backdated)

        let comps = calendar.dateComponents([.month, .day], from: try XCTUnwrap(next))
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 18, "cadence advances from the DOSE date, not from now")
    }

    func testNextDueIsPureAndDoesNotMutate() throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let before = med.startedAt

        _ = logger(now: { now }).nextDue(for: med, after: now)

        XCTAssertEqual(med.startedAt, before, "nextDue must not write to the medication")
        XCTAssertEqual(try logStore.doseCount(for: med), 0)
    }
}
