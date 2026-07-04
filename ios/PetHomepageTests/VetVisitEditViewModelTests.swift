// ios/PetHomepageTests/VetVisitEditViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VetVisitEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!
    private var veterinarianStore: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
    }

    private func makeVM(editing: LogEntry? = nil, cadenceMonths: Int = 6,
                        dueScheduler: DueReminderScheduler) -> VetVisitEditViewModel {
        VetVisitEditViewModel(logStore: logStore, dueScheduler: dueScheduler,
                              cadenceMonths: cadenceMonths, veterinarianStore: veterinarianStore,
                              editing: editing)
    }

    func testSaveCreatesNewVisitAndResyncsCadence() async throws {
        let fake = FakeNotificationScheduler()
        let dueScheduler = DueReminderScheduler(scheduler: fake)
        let vm = makeVM(dueScheduler: dueScheduler)
        vm.occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        vm.clinicName = "Paws Clinic"
        vm.vetName = "Dr. V"
        vm.reason = "Checkup"
        vm.diagnosis = "Healthy"
        vm.treatmentNotes = "None"

        try await vm.save()

        let saved = try logStore.vetVisits()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.clinicName, "Paws Clinic")
        XCTAssertEqual(saved.first?.title, "Checkup")
        let pending = await fake.pendingIDs(kind: .vetCadence)
        XCTAssertEqual(pending.count, 1, "saving a visit should (re)schedule the vet-cadence reminder")
    }

    func testEditingExistingVisitPrefillsFields() throws {
        let visit = try logStore.logVetVisit(occurredAt: Date(timeIntervalSince1970: 1),
                                             clinicName: "Bayside", vetName: "Dr. Ruth",
                                             reason: "Limp", diagnosis: "Sprain",
                                             treatmentNotes: "Rest", nextVisitDate: Date(timeIntervalSince1970: 500))

        let vm = makeVM(editing: visit, dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()))

        XCTAssertEqual(vm.clinicName, "Bayside")
        XCTAssertEqual(vm.vetName, "Dr. Ruth")
        XCTAssertEqual(vm.reason, "Limp")
        XCTAssertEqual(vm.diagnosis, "Sprain")
        XCTAssertEqual(vm.treatmentNotes, "Rest")
        XCTAssertTrue(vm.hasNextVisit)
    }

    func testSaveUpdatesExistingVisitInPlace() async throws {
        let visit = try logStore.logVetVisit(occurredAt: Date(timeIntervalSince1970: 1),
                                             clinicName: "Bayside", vetName: nil, reason: nil,
                                             diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let vm = makeVM(editing: visit, dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()))
        vm.clinicName = "Bayside (updated)"

        try await vm.save()

        XCTAssertEqual(try logStore.vetVisits().count, 1)
        XCTAssertEqual(try logStore.vetVisits().first?.clinicName, "Bayside (updated)")
    }
}
