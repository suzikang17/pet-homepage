// ios/PetHomepageTests/VaccinationEditViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class VaccinationEditViewModelTests: XCTestCase {
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

    func testSaveCreatesAndSchedulesDueReminder() async throws {
        let vm = VaccinationEditViewModel(store: store, dueScheduler: dueScheduler,
                                          veterinarianStore: veterinarianStore, editing: nil)
        vm.vaccineName = "Rabies"
        vm.administeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hasNextDue = true
        vm.nextDueAt = Date(timeIntervalSince1970: 1_900_000_000)

        try await vm.save()

        XCTAssertEqual(try store.vaccinations().count, 1)
        let pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertEqual(pending.count, 1)
    }
}
