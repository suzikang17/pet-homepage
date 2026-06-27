// ios/PetHomepageTests/VaccinationsListViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VaccinationsListViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: VaccinationStore!
    private var dueScheduler: DueReminderScheduler!
    private var fake: FakeNotificationScheduler!
    private var veterinarianStore: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = VaccinationStore(context: context, petStore: petStore)
        veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        dueScheduler = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian))
    }

    func testLoadBuildsRowsWithLastAndNext() throws {
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        try store.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1_700_000_000),
                         nextDueAt: due, lotNumber: nil, administeredBy: nil)
        let vm = VaccinationsListViewModel(store: store, dueScheduler: dueScheduler)

        try vm.load()

        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows.first?.vaccineName, "Rabies")
        XCTAssertNotNil(vm.rows.first?.lastGiven)
        XCTAssertEqual(vm.rows.first?.nextDue, due)
    }

    func testEditViewModelSaveCreatesAndSchedulesDueReminder() async throws {
        let vm = VaccinationEditViewModel(store: store, dueScheduler: dueScheduler, veterinarianStore: veterinarianStore, editing: nil)
        vm.vaccineName = "Rabies"
        vm.administeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hasNextDue = true
        vm.nextDueAt = Date(timeIntervalSince1970: 1_900_000_000)

        try await vm.save()

        XCTAssertEqual(try store.vaccinations().count, 1)
        let pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertEqual(pending.count, 1)
    }

    func testDeleteCancelsReminderAndRemovesRow() async throws {
        let vax = try store.create(vaccineName: "Rabies", administeredAt: Date(timeIntervalSince1970: 1),
                                   nextDueAt: Date(timeIntervalSince1970: 1_900_000_000), lotNumber: nil, administeredBy: nil)
        await dueScheduler.syncVaccination(vax)
        let vm = VaccinationsListViewModel(store: store, dueScheduler: dueScheduler)
        try vm.load()

        try await vm.delete(vm.rows[0])

        XCTAssertTrue(try store.vaccinations().isEmpty)
        let pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertTrue(pending.isEmpty)
    }
}
