// ios/PetHomepageTests/LogDoseViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class LogDoseViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: MedicationStore!
    private var logStore: LogStore!
    private var reminderScheduler: MedicationReminderScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        reminderScheduler = MedicationReminderScheduler(
            scheduler: FakeNotificationScheduler(),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func makeMed(frequency: String) throws -> Medication {
        let cal = Calendar(identifier: .gregorian)
        let eightAM = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8))!
        return try store.create(drugName: "Apoquel", dosage: "16mg", frequency: frequency,
                                scheduleTime: eightAM, nextReminderAt: eightAM, endedAt: nil, refillDueAt: nil)
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
        logStore = nil
        reminderScheduler = nil
    }

    func testNextReminderIsOneIntervalAfterDoseAtScheduleTime() throws {
        let vm = LogDoseViewModel(medication: try makeMed(frequency: "Every 3 days"),
                                  logStore: logStore, reminderScheduler: reminderScheduler)
        let cal = Calendar(identifier: .gregorian)
        vm.givenAt = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 14))! // Jun 10, 2pm

        let next = vm.nextReminder(calendar: cal)

        let expected = cal.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 8))! // +3d at 8am
        XCTAssertEqual(next, expected)
    }

    @MainActor
    func testConfirmRecordsDoseWithNoteAndReschedules() async throws {
        let med = try makeMed(frequency: "Every 3 days")
        let vm = LogDoseViewModel(medication: med, logStore: logStore, reminderScheduler: reminderScheduler)
        vm.givenAt = Date(timeIntervalSince1970: 1_000_000)
        vm.note = "with food"

        await vm.confirm()

        XCTAssertTrue(vm.isConfirmed)
        XCTAssertEqual(vm.doseCount, 1)
        XCTAssertNotNil(vm.confirmedNextReminder)
        XCTAssertEqual(med.nextReminder, vm.confirmedNextReminder, "logging a dose reschedules the next reminder")
        let logs = try logStore.doses(for: med)
        XCTAssertEqual(logs.first?.note, "with food")
        XCTAssertEqual(logs.first?.performedAt, Date(timeIntervalSince1970: 1_000_000))
    }
}
