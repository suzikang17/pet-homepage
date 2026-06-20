// ios/PetHomepageTests/VetVisitsListViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VetVisitsListViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: VetVisitStore!
    private var dueScheduler: DueReminderScheduler!
    private var fake: FakeNotificationScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = VetVisitStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        dueScheduler = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian))
    }

    func testLoadBuildsRowsAndSchedulesCadenceFromMostRecentVisit() async throws {
        try store.create(occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                         clinicName: "Paws", vetName: nil, reason: "Exam",
                         diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let vm = VetVisitsListViewModel(store: store, dueScheduler: dueScheduler, cadenceMonths: 6)

        try vm.load()
        await vm.syncCadence()

        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows.first?.clinicName, "Paws")
        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(pending.count, 1)
    }

    func testDeleteRemovesRow() async throws {
        let visit = try store.create(occurredAt: Date(timeIntervalSince1970: 1),
                                     clinicName: "A", vetName: nil, reason: nil,
                                     diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let vm = VetVisitsListViewModel(store: store, dueScheduler: dueScheduler, cadenceMonths: 6)
        try vm.load()

        try await vm.delete(VetVisitRow(id: visit.id!, visit: visit, occurredAt: visit.occurredAtValue,
                                        clinicName: "A", reason: nil))

        XCTAssertTrue(try store.visits().isEmpty)
    }
}
