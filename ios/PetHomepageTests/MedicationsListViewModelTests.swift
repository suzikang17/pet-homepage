// ios/PetHomepageTests/MedicationsListViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class MedicationsListViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!
    private var doseStore: DoseLogStore!
    private var reminderScheduler: MedicationReminderScheduler!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        doseStore = DoseLogStore(context: context)
        calendar = Calendar(identifier: .gregorian)
        reminderScheduler = MedicationReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar)
    }

    private func makeVM() -> MedicationsListViewModel {
        MedicationsListViewModel(medicationStore: medStore,
                                 doseLogStore: doseStore,
                                 reminderScheduler: reminderScheduler,
                                 calendar: calendar)
    }

    private func makeMed(_ name: String, refillDueAt: Date? = nil) throws -> Medication {
        let t = Date(timeIntervalSince1970: 0)
        return try medStore.create(drugName: name, dosage: "1", frequency: "daily",
                                   scheduleTime: t, startedAt: t, refillDueAt: refillDueAt)
    }

    func testLoadBuildsRowsForEachMedication() throws {
        _ = try makeMed("Apoquel")
        _ = try makeMed("Zyrtec")
        let vm = makeVM()

        try vm.load()

        XCTAssertEqual(vm.rows.map(\.drugName), ["Apoquel", "Zyrtec"])
        XCTAssertNil(vm.rows.first?.lastGiven)
    }

    func testLogDoseUpdatesLastGiven() async throws {
        _ = try makeMed("Apoquel")
        let vm = makeVM()
        try vm.load()
        let when = Date(timeIntervalSince1970: 5_000)

        try await vm.logDose(vm.rows[0], at: when)

        XCTAssertEqual(vm.rows[0].lastGiven, when)
    }

    func testRefillDueSoonFlagsMedicationsWithinSevenDays() throws {
        let soon = calendar.date(byAdding: .day, value: 3, to: Date())!
        let far = calendar.date(byAdding: .day, value: 30, to: Date())!
        _ = try makeMed("Apoquel", refillDueAt: soon)
        _ = try makeMed("Zyrtec", refillDueAt: far)
        let vm = makeVM()

        try vm.load()

        let apoquel = vm.rows.first { $0.drugName == "Apoquel" }
        let zyrtec = vm.rows.first { $0.drugName == "Zyrtec" }
        XCTAssertTrue(apoquel?.isRefillDueSoon == true)
        XCTAssertFalse(zyrtec?.isRefillDueSoon == true)
    }

    func testNextDueIsInTheFuture() throws {
        _ = try makeMed("Apoquel")
        let vm = makeVM()

        try vm.load()

        let nextDue = try XCTUnwrap(vm.rows.first?.nextDue)
        XCTAssertGreaterThan(nextDue, Date())
    }

    func testDeleteRemovesRow() async throws {
        _ = try makeMed("Apoquel")
        let vm = makeVM()
        try vm.load()

        try await vm.delete(vm.rows[0])

        XCTAssertTrue(vm.rows.isEmpty)
    }

    func testHasAnyRefillDueSoonReflectsRows() throws {
        let soon = calendar.date(byAdding: .day, value: 3, to: Date())!
        let far = calendar.date(byAdding: .day, value: 30, to: Date())!
        _ = try makeMed("Apoquel", refillDueAt: far)
        let vm = makeVM()
        try vm.load()

        XCTAssertFalse(vm.hasAnyRefillDueSoon)

        _ = try makeMed("Zyrtec", refillDueAt: soon)
        try vm.load()

        XCTAssertTrue(vm.hasAnyRefillDueSoon)
    }
}
