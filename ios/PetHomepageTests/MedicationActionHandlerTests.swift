// ios/PetHomepageTests/MedicationActionHandlerTests.swift
import XCTest
import CoreData
import UserNotifications
@testable import PetHomepage

@MainActor
final class MedicationActionHandlerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!
    private var logStore: LogStore!
    private var petStore: PetStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    override func tearDownWithError() throws {
        context = nil
        medStore = nil
        logStore = nil
        petStore = nil
        calendar = nil
    }

    private func makeMonthlyMed() throws -> Medication {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        return try medStore.create(drugName: "Simparica", dosage: "1 chew", frequency: "Monthly",
                                   scheduleTime: start, startedAt: start, refillDueAt: nil)
    }

    private func handler(now: @escaping () -> Date,
                         scheduler: FakeNotificationScheduler) -> MedicationActionHandler {
        MedicationActionHandler(context: context, scheduler: scheduler,
                                calendar: calendar, now: now)
    }

    func testLogDoseActionRecordsDoseAndAdvancesCadence() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let fake = FakeNotificationScheduler()
        let sut = handler(now: { fixedNow }, scheduler: fake)

        await sut.handle(actionID: MedicationNotificationAction.logDose,
                         requestID: ReminderIdentifier.requestID(kind: .medication, entityID: med.id))

        XCTAssertEqual(try logStore.doseCount(for: med), 1, "the action should record one dose")
        // Cadence advances a month from the dose, at the medication's scheduled time.
        let next = try XCTUnwrap(calendar.dateComponents([.year, .month, .day], from: med.startedAt) as DateComponents?)
        XCTAssertEqual(next.month, 4)
        XCTAssertEqual(next.day, 14)
    }

    /// Acting on a banner that's still on the lock screen after the dose was logged in-app must
    /// not record a second dose.
    func testLogDoseIsIdempotentWithinTheSameDay() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let fake = FakeNotificationScheduler()
        let sut = handler(now: { fixedNow }, scheduler: fake)
        let requestID = ReminderIdentifier.requestID(kind: .medication, entityID: med.id)

        await sut.handle(actionID: MedicationNotificationAction.logDose, requestID: requestID)
        await sut.handle(actionID: MedicationNotificationAction.logDose, requestID: requestID)

        XCTAssertEqual(try logStore.doseCount(for: med), 1, "a stale notification must not double-log")
    }

    /// The snooze must be its own kind: a monthly medication now carries a REPEATING trigger, and
    /// a snooze sharing its identifier would replace the entire future cadence with one re-fire.
    func testSnoozeDoesNotReplaceTheMedicationReminder() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let fake = FakeNotificationScheduler()
        let reminderScheduler = MedicationReminderScheduler(scheduler: fake, calendar: calendar,
                                                            now: { fixedNow })
        await reminderScheduler.sync(med)
        let sut = handler(now: { fixedNow }, scheduler: fake)

        await sut.handle(actionID: MedicationNotificationAction.snooze,
                         requestID: ReminderIdentifier.requestID(kind: .medication, entityID: med.id))

        let meds = await fake.pendingIDs(kind: .medication)
        let snoozes = await fake.pendingIDs(kind: .medicationSnooze)
        XCTAssertEqual(meds, [med.id], "the repeating medication reminder must survive a snooze")
        XCTAssertEqual(snoozes, [med.id], "the snooze should be scheduled under its own kind")
    }

    func testSnoozedReminderCanItselfBeLogged() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 10))!
        let fake = FakeNotificationScheduler()
        let sut = handler(now: { fixedNow }, scheduler: fake)

        await sut.handle(
            actionID: MedicationNotificationAction.logDose,
            requestID: ReminderIdentifier.requestID(kind: .medicationSnooze, entityID: med.id))

        XCTAssertEqual(try logStore.doseCount(for: med), 1,
                       "a snoozed re-fire resolves to the same medication")
    }

    func testIgnoresNonMedicationRequestIDs() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let fake = FakeNotificationScheduler()
        let sut = handler(now: { fixedNow }, scheduler: fake)

        await sut.handle(actionID: MedicationNotificationAction.logDose,
                         requestID: ReminderIdentifier.requestID(kind: .routine, entityID: med.id))

        XCTAssertEqual(try logStore.doseCount(for: med), 0)
    }

    func testPlainTapDoesNotLogADose() async throws {
        let med = try makeMonthlyMed()
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let fake = FakeNotificationScheduler()
        let sut = handler(now: { fixedNow }, scheduler: fake)

        await sut.handle(actionID: UNNotificationDefaultActionIdentifier,
                         requestID: ReminderIdentifier.requestID(kind: .medication, entityID: med.id))

        XCTAssertEqual(try logStore.doseCount(for: med), 0,
                       "opening the app from a banner must not silently record a dose")
    }
}
