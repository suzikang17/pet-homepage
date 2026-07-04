// ios/PetHomepageTests/CaptureReviewViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class CaptureReviewViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var activityStore: ActivityStore!
    private var medicationStore: MedicationStore!
    private var logStore: LogStore!
    private var fake: FakeNotificationScheduler!
    private var sched: DueReminderScheduler!

    private let samplePhoto = Data([0xFF, 0xD8, 0xFF, 0xD9])

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        activityStore = ActivityStore(context: context, petStore: petStore)
        medicationStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        sched = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian), hour: 9, minute: 0)
    }

    private func makeModel() -> CaptureReviewViewModel {
        CaptureReviewViewModel(
            photo: samplePhoto,
            logStore: logStore,
            activityStore: activityStore,
            medicationStore: medicationStore,
            dueScheduler: sched
        )
    }

    func testSaveUntaggedCreatesDiaryEntryWithPhoto() async throws {
        let vm = makeModel()
        vm.note = "Just a snapshot"
        vm.performedAt = Date(timeIntervalSince1970: 0)
        try await vm.save()

        let entries = try logStore.diaryEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.note, "Just a snapshot")
        XCTAssertEqual(entries.first?.photoArray.count, 1)
    }

    func testSaveWithActivityTagLogsActivityAndSchedulesReminder() async throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let vm = makeModel()
        vm.tag = .activity(type)
        vm.performedAt = Date(timeIntervalSince1970: 0)
        try await vm.save()

        let logs = try logStore.activityLogs()
        XCTAssertEqual(logs.count, 1)
        let entry = try XCTUnwrap(logs.first)
        XCTAssertNotNil(entry.nextDueAt)
        XCTAssertEqual(entry.photoArray.count, 1)

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [entry.id])
    }

    func testSecondActivitySaveCancelsPriorReminder() async throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)

        let vm1 = makeModel()
        vm1.tag = .activity(type)
        vm1.performedAt = Date(timeIntervalSince1970: 0)
        try await vm1.save()
        let firstID = try logStore.latestLog(of: type)!.id

        let vm2 = makeModel()
        vm2.tag = .activity(type)
        vm2.performedAt = Date(timeIntervalSince1970: 10_000)
        try await vm2.save()

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending.count, 1, "only the latest log should have a pending reminder")
        XCTAssertFalse(pending.contains(firstID))
    }

    func testSaveWithMedicationTagLogsDoseWithPhoto() async throws {
        let med = try medicationStore.create(
            drugName: "Rimadyl",
            dosage: "50mg",
            frequency: "Once daily",
            scheduleTime: Date(timeIntervalSince1970: 0),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            refillDueAt: nil
        )
        let vm = makeModel()
        vm.tag = .medication(med)
        try await vm.save()

        let doses = try logStore.doses(for: med)
        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(doses.first?.kind, .dose)
        XCTAssertEqual(doses.first?.photoArray.count, 1)
    }

    func testActiveMedFilteringExcludesEndedMedications() throws {
        let ended = try medicationStore.create(
            drugName: "Old med",
            dosage: "10mg",
            frequency: "Once daily",
            scheduleTime: Date(),
            startedAt: Date(timeIntervalSinceNow: -1000),
            endedAt: Date(timeIntervalSinceNow: -100),
            refillDueAt: nil
        )
        let current = try medicationStore.create(
            drugName: "Current med",
            dosage: "20mg",
            frequency: "Twice daily",
            scheduleTime: Date(),
            startedAt: Date(timeIntervalSinceNow: -1000),
            endedAt: nil,
            refillDueAt: nil
        )

        let vm = makeModel()
        XCTAssertFalse(vm.activeMeds.contains { $0.id == ended.id })
        XCTAssertTrue(vm.activeMeds.contains { $0.id == current.id })
    }
}
