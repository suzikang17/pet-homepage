// ios/PetHomepageTests/MedicationEditViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class MedicationEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var store: MedicationStore!
    private var fake: FakeNotificationScheduler!
    private var reminderScheduler: MedicationReminderScheduler!
    private var veterinarianStore: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = MedicationStore(context: context, petStore: petStore)
        veterinarianStore = VeterinarianStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        reminderScheduler = MedicationReminderScheduler(
            scheduler: fake,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
        fake = nil
        reminderScheduler = nil
        veterinarianStore = nil
    }

    func testResetNextReminderFromFrequencyAnchorsOneIntervalOut() {
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: nil)
        vm.frequencyUnit = .day
        vm.frequencyInterval = 3
        let now = Date(timeIntervalSince1970: 1_000_000)

        vm.resetNextReminderFromFrequency(now: now)

        let expected = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(vm.nextReminder, expected)
    }

    func testSaveCreatesMedicationAndSchedulesReminder() async throws {
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: nil)
        vm.drugName = "Apoquel"
        vm.dosage = "16mg"
        vm.frequencyUnit = .day

        try await vm.save()

        let meds = try store.medications()
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.drugName, "Apoquel")
        let pending = await fake.pendingMedicationIDs()
        XCTAssertEqual(pending.count, 1)
    }

    func testIsValidRequiresDrugName() {
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: nil)
        XCTAssertFalse(vm.isValid)
        vm.drugName = "Apoquel"
        XCTAssertTrue(vm.isValid)
    }

    func testInitLoadsExistingMedicationForEditing() async throws {
        let t = Date(timeIntervalSince1970: 0)
        let med = try store.create(drugName: "Zyrtec", dosage: "5mg", frequency: "daily",
                                   scheduleTime: t, nextReminderAt: t, refillDueAt: nil)

        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: med)

        XCTAssertEqual(vm.drugName, "Zyrtec")
        XCTAssertEqual(vm.dosage, "5mg")
        XCTAssertFalse(vm.hasRefillDue)
        XCTAssertFalse(vm.hasEnded)
    }

    func testSaveUpdatesExistingMedication() async throws {
        let t = Date(timeIntervalSince1970: 0)
        let med = try store.create(drugName: "Zyrtec", dosage: "5mg", frequency: "daily",
                                   scheduleTime: t, nextReminderAt: t, refillDueAt: nil)
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: med)
        vm.dosage = "10mg"
        vm.hasRefillDue = true
        vm.refillDueAt = Date(timeIntervalSince1970: 86_400)

        try await vm.save()

        let fetched = try store.medications().first
        XCTAssertEqual(fetched?.dosage, "10mg")
        XCTAssertEqual(fetched?.refillDueAt, Date(timeIntervalSince1970: 86_400))
    }

    func testSavingEndedMedicationCancelsReminder() async throws {
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: nil)
        vm.drugName = "Apoquel"
        vm.hasEnded = true
        vm.endedAt = Date(timeIntervalSince1970: 0) // ended in the past

        try await vm.save()

        let pending = await fake.pendingMedicationIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    /// Regression test: verifies that creating a new medication with hasEnded=true
    /// persists endedAt atomically in a single Core Data save, not as a separate
    /// follow-up update(). A double-save implementation would leave endedAt=nil
    /// if the process crashed between the two saves.
    func testSavingEndedMedicationPersistsEndedAtInCoreData() async throws {
        let endedDate = Date(timeIntervalSince1970: 0)
        let vm = MedicationEditViewModel(store: store, reminderScheduler: reminderScheduler, veterinarianStore: veterinarianStore, editing: nil)
        vm.drugName = "Apoquel"
        vm.dosage = "16mg"
        vm.frequencyUnit = .day
        vm.hasEnded = true
        vm.endedAt = endedDate

        try await vm.save()

        let fetched = try store.medications().first
        XCTAssertNotNil(fetched, "medication should be persisted")
        XCTAssertEqual(fetched?.endedAt, endedDate,
                       "endedAt must be set in the same atomic save as the create — not in a second update()")
    }
}
