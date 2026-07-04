// ios/PetHomepageTests/VaccinationEditViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class VaccinationEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!
    private var dueScheduler: DueReminderScheduler!
    private var fake: FakeNotificationScheduler!
    private var veterinarianStore: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        dueScheduler = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian))
    }

    func testSaveCreatesAndSchedulesDueReminder() async throws {
        let vm = VaccinationEditViewModel(logStore: logStore, dueScheduler: dueScheduler,
                                          veterinarianStore: veterinarianStore, editing: nil)
        vm.vaccineName = "Rabies"
        vm.administeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hasNextDue = true
        vm.nextDueAt = Date(timeIntervalSince1970: 1_900_000_000)

        try await vm.save()

        XCTAssertEqual(try logStore.vaccines().count, 1)
        let pending = await fake.pendingIDs(kind: .vaccination)
        XCTAssertEqual(pending.count, 1)
    }

    /// Capture-sheet handoff: a "Vaccine" tag on a captured photo opens this editor with the
    /// photo already staged as a pending photo (vaccination has required fields, so it can't
    /// instant-save from the capture sheet).
    func testInitialPhotoSeedsPendingPhotos() {
        let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let vm = VaccinationEditViewModel(logStore: logStore, dueScheduler: dueScheduler,
                                          veterinarianStore: veterinarianStore, editing: nil,
                                          initialPhoto: photo)

        XCTAssertEqual(vm.pendingPhotos, [photo])
    }
}
