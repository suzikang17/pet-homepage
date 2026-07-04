// ios/PetHomepageTests/TimelineViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class TimelineViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var vetVisitStore: VetVisitStore!
    private var medicationStore: MedicationStore!
    private var healthMarkerStore: HealthMarkerStore!
    private var symptomEpisodeStore: SymptomEpisodeStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        medicationStore = MedicationStore(context: context, petStore: petStore)
        healthMarkerStore = HealthMarkerStore(context: context, petStore: petStore)
        symptomEpisodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
    }

    private func makeVM() -> TimelineViewModel {
        TimelineViewModel(
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            logStore: logStore
        )
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    func testLoadAggregatesEveryTypeNewestFirst() throws {
        _ = try logStore.logVaccine(name: "Rabies", performedAt: day(10), nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        _ = try vetVisitStore.create(occurredAt: day(30), clinicName: "Bayside", vetName: nil, reason: "Checkup", diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        _ = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: day(20), startedAt: day(20), endedAt: nil, refillDueAt: nil)
        try healthMarkerStore.create(markerType: .weight, value: 31, unit: "kg", recordedAt: day(5))

        let vm = makeVM()
        vm.load()

        XCTAssertEqual(vm.items.count, 4)
        XCTAssertEqual(vm.items.map(\.kind), [.vet, .medication, .vaccine, .marker])
    }

    func testFilterRestrictsToOneKind() throws {
        _ = try logStore.logVaccine(name: "Rabies", performedAt: day(1), nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        _ = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: day(1), startedAt: day(1), endedAt: nil, refillDueAt: nil)

        let vm = makeVM()
        vm.load()
        vm.filter = .medication

        XCTAssertEqual(vm.filtered.map(\.kind), [.medication])
    }

    func testDueSoonReturnsUpcomingNextDuesSortedAscendingWithinHorizon() throws {
        let now = day(1_000)
        let inDays: (Int) -> Date = { now.addingTimeInterval(Double($0) * 86_400) }
        _ = try logStore.logVaccine(name: "DHPP", performedAt: now, nextDueAt: inDays(20), lotNumber: nil, administeredBy: nil)
        _ = try vetVisitStore.create(occurredAt: now, clinicName: "Bayside", vetName: nil, reason: nil, diagnosis: nil, treatmentNotes: nil, nextVisitDate: inDays(5))
        _ = try medicationStore.create(drugName: "X", dosage: "", frequency: "", scheduleTime: now, startedAt: now, endedAt: nil, refillDueAt: inDays(90))

        let vm = makeVM()
        vm.load()
        let due = vm.dueSoon(within: 30, now: now)

        XCTAssertEqual(due.count, 2) // the 90-day refill is beyond the horizon
        XCTAssertEqual(due.map(\.kind), [.vet, .vaccine]) // 5 days before 20 days
    }

    private func makeServices(reminderScheduler: MedicationReminderScheduler,
                              dueScheduler: DueReminderScheduler) -> TimelineServices {
        TimelineServices(
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            veterinarianStore: VeterinarianStore(context: context, petStore: PetStore(context: context)),
            diaryStore: DiaryStore(context: context, petStore: PetStore(context: context)),
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            symptomEntryStore: SymptomEntryStore(context: context),
            recommendationStore: VetRecommendationStore(context: context),
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: reminderScheduler,
            dueScheduler: dueScheduler,
            cadenceMonths: 6,
            extractionService: nil,
            ingestionService: nil
        )
    }

    func testDeleteMedicationRemovesItAndCancelsReminder() async throws {
        let fake = FakeNotificationScheduler()
        let reminderScheduler = MedicationReminderScheduler(scheduler: fake)
        let med = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                             scheduleTime: day(1), startedAt: day(1), endedAt: nil, refillDueAt: nil)
        await reminderScheduler.sync(med)
        let before = await fake.pendingIDs(kind: .medication)
        XCTAssertEqual(before, [med.id])

        let vm = makeVM()
        vm.load()
        let item = try XCTUnwrap(vm.items.first { $0.kind == .medication })
        await vm.delete(item, using: makeServices(
            reminderScheduler: reminderScheduler,
            dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler())))

        XCTAssertTrue(vm.items.isEmpty)
        let after = await fake.pendingIDs(kind: .medication)
        XCTAssertTrue(after.isEmpty, "reminder should be cancelled on delete")
    }

    func testDeleteVaccinationRemovesItAndCancelsDueReminder() async throws {
        let fake = FakeNotificationScheduler()
        let dueScheduler = DueReminderScheduler(scheduler: fake)
        let vax = try logStore.logVaccine(name: "Rabies", performedAt: day(1),
                                          nextDueAt: day(400), lotNumber: nil, administeredBy: nil)
        await dueScheduler.syncVaccination(vax)
        let before = await fake.pendingIDs(kind: .vaccination)
        XCTAssertFalse(before.isEmpty)

        let vm = makeVM()
        vm.load()
        let item = try XCTUnwrap(vm.items.first { $0.kind == .vaccine })
        await vm.delete(item, using: makeServices(
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler()),
            dueScheduler: dueScheduler))

        XCTAssertTrue(vm.items.isEmpty)
        let after = await fake.pendingIDs(kind: .vaccination)
        XCTAssertTrue(after.isEmpty, "due reminder should be cancelled on delete")
    }

    func testDeleteLatestActivityReArmsPriorLogReminder() async throws {
        let fake = FakeNotificationScheduler()
        let dueScheduler = DueReminderScheduler(scheduler: fake)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let older = try logStore.logActivity(type: type, performedAt: day(10), note: nil, intervalDays: 30)
        let newer = try logStore.logActivity(type: type, performedAt: day(40), note: nil, intervalDays: 30)
        // Only the newest log holds a pending reminder (the edit VM enforces this when logging;
        // set that state up directly here to mirror it).
        await dueScheduler.syncActivity(newer)

        let vm = makeVM()
        vm.load()
        let item = try XCTUnwrap(vm.items.first { $0.id == "activity:\(newer.id.uuidString)" })
        await vm.delete(item, using: makeServices(
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler()),
            dueScheduler: dueScheduler))

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [older.id], "deleting the latest log should re-arm the prior log's reminder")
    }

    func testActivityLogsAppearInStreamAndDueSoon() throws {
        // Uses the same in-memory context + petStore the other tests build.
        let context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        let activityStore = ActivityStore(context: context, petStore: petStore)
        let logStore = LogStore(context: context, petStore: petStore)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 7)
        _ = try logStore.logActivity(type: type, performedAt: Date(), note: nil, intervalDays: 7)

        let vm = TimelineViewModel(
            vetVisitStore: VetVisitStore(context: context, petStore: petStore),
            medicationStore: MedicationStore(context: context, petStore: petStore),
            healthMarkerStore: HealthMarkerStore(context: context, petStore: petStore),
            symptomEpisodeStore: SymptomEpisodeStore(context: context, petStore: petStore),
            logStore: logStore
        )
        vm.load()

        XCTAssertTrue(vm.items.contains { $0.kind == .activity && $0.title == "Bath" })
        XCTAssertTrue(vm.dueSoon(within: 30).contains { $0.kind == .activity })
    }
}
