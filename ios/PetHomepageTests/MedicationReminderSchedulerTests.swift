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
                                      scheduleTime: scheduleTime, startedAt: scheduleTime, refillDueAt: nil)
        if ended {
            med.endedAt = Date(timeIntervalSince1970: 0) // far in the past
            try context.save()
        }
        return med
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
}
