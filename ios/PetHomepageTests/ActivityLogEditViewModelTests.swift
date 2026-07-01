// ios/PetHomepageTests/ActivityLogEditViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class ActivityLogEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: ActivityStore!
    private var logStore: LogStore!
    private var fake: FakeNotificationScheduler!
    private var sched: DueReminderScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        sched = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian), hour: 9, minute: 0)
    }

    func testSelectingTypeAdoptsItsDefaultCadence() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let vm = ActivityLogEditViewModel(logStore: logStore, store: store, dueScheduler: sched, editing: nil)
        vm.selectType(type)
        XCTAssertTrue(vm.hasCadence)
        XCTAssertEqual(vm.intervalDays, 30)
        XCTAssertTrue(vm.isValid)
    }

    func testCreateNewTypeFromInlineFields() throws {
        let vm = ActivityLogEditViewModel(logStore: logStore, store: store, dueScheduler: sched, editing: nil)
        vm.newTypeName = "Ear cleaning"
        vm.newTypeCategory = .care
        try vm.createAndSelectNewType()
        XCTAssertEqual(vm.selectedType?.name, "Ear cleaning")
        XCTAssertTrue(try store.types().contains { $0.name == "Ear cleaning" })
    }

    func testSaveLogsAndSchedulesReminder() async throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let vm = ActivityLogEditViewModel(logStore: logStore, store: store, dueScheduler: sched, editing: nil)
        vm.selectType(type)
        vm.performedAt = Date(timeIntervalSince1970: 0)
        try await vm.save()

        XCTAssertEqual(try logStore.activityLogs().count, 1)
        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending.count, 1)
    }

    func testSaveCancelsPriorLatestReminderOfSameType() async throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        // First log + its reminder.
        let vm1 = ActivityLogEditViewModel(logStore: logStore, store: store, dueScheduler: sched, editing: nil)
        vm1.selectType(type)
        vm1.performedAt = Date(timeIntervalSince1970: 0)
        try await vm1.save()
        let firstID = try logStore.latestLog(of: type)!.id

        // Second log should cancel the first's reminder and schedule its own.
        let vm2 = ActivityLogEditViewModel(logStore: logStore, store: store, dueScheduler: sched, editing: nil)
        vm2.selectType(type)
        vm2.performedAt = Date(timeIntervalSince1970: 10_000)
        try await vm2.save()

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending.count, 1, "only the latest log should have a pending reminder")
        XCTAssertFalse(pending.contains(firstID))
    }
}
