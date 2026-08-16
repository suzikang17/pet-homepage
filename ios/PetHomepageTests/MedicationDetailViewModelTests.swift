// ios/PetHomepageTests/MedicationDetailViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

@MainActor
final class MedicationDetailViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: MedicationStore!
    private var logStore: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
    }

    private func makeVM(_ med: Medication) -> MedicationDetailViewModel {
        MedicationDetailViewModel(
            medication: med, logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler()))
    }

    private func makeMed() throws -> Medication {
        try store.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                         scheduleTime: Date(), startedAt: Date(), endedAt: nil, refillDueAt: nil)
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
        logStore = nil
    }

    func testLogDoseAppendsAndOrdersNewestFirst() async throws {
        let vm = makeVM(try makeMed())
        XCTAssertEqual(vm.doseCount, 0)
        XCTAssertNil(vm.lastGiven)

        await vm.logDose(at: Date(timeIntervalSince1970: 100))
        await vm.logDose(at: Date(timeIntervalSince1970: 500))

        XCTAssertEqual(vm.doseCount, 2)
        XCTAssertEqual(vm.lastGiven, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(vm.doses.first?.performedAt, Date(timeIntervalSince1970: 500))
    }

    func testDeleteDoseRemovesIt() async throws {
        let vm = makeVM(try makeMed())
        await vm.logDose(at: Date(timeIntervalSince1970: 100))
        let dose = try XCTUnwrap(vm.doses.first)

        await vm.deleteDose(dose)

        XCTAssertEqual(vm.doseCount, 0)
        XCTAssertNil(vm.lastGiven)
    }

    /// Deleting a dose used to be a half-undo: the entry vanished but `startedAt` — this model's
    /// next-reminder date — stayed advanced, so the reminder pointed a full interval past a dose
    /// that no longer existed.
    func testDeletingTheNewestDoseMovesTheCadenceBackToThePreviousOne() async throws {
        let cal = Calendar(identifier: .gregorian)
        let day1 = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let day5 = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9))!
        let med = try store.create(drugName: "Simparica", dosage: "1 chew", frequency: "Monthly",
                                   scheduleTime: day1, startedAt: day1, endedAt: nil,
                                   refillDueAt: nil)
        let vm = MedicationDetailViewModel(
            medication: med, logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: cal),
            calendar: cal)

        await vm.logDose(at: day1)
        await vm.logDose(at: day5)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: med.startedAt).day, 5,
                       "cadence follows the newest dose (5 Mar + 1 month)")

        await vm.deleteDose(try XCTUnwrap(vm.doses.first))   // remove the 5 Mar dose

        let comps = cal.dateComponents([.month, .day], from: med.startedAt)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1, "cadence must fall back to follow the 1 Mar dose")
    }
}
