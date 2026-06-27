// ios/PetHomepageTests/TimelineViewModelTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class TimelineViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var vaccinationStore: VaccinationStore!
    private var vetVisitStore: VetVisitStore!
    private var medicationStore: MedicationStore!
    private var healthMarkerStore: HealthMarkerStore!
    private var symptomEpisodeStore: SymptomEpisodeStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vaccinationStore = VaccinationStore(context: context, petStore: petStore)
        vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        medicationStore = MedicationStore(context: context, petStore: petStore)
        healthMarkerStore = HealthMarkerStore(context: context, petStore: petStore)
        symptomEpisodeStore = SymptomEpisodeStore(context: context, petStore: petStore)
    }

    private func makeVM() -> TimelineViewModel {
        TimelineViewModel(
            vaccinationStore: vaccinationStore,
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore
        )
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    func testLoadAggregatesEveryTypeNewestFirst() throws {
        _ = try vaccinationStore.create(vaccineName: "Rabies", administeredAt: day(10), nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        _ = try vetVisitStore.create(occurredAt: day(30), clinicName: "Bayside", vetName: nil, reason: "Checkup", diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        _ = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: day(20), startedAt: day(20), endedAt: nil, refillDueAt: nil)
        try healthMarkerStore.create(markerType: .weight, value: 31, unit: "kg", recordedAt: day(5))

        let vm = makeVM()
        vm.load()

        XCTAssertEqual(vm.items.count, 4)
        XCTAssertEqual(vm.items.map(\.kind), [.vet, .medication, .vaccine, .marker])
    }

    func testFilterRestrictsToOneKind() throws {
        _ = try vaccinationStore.create(vaccineName: "Rabies", administeredAt: day(1), nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        _ = try medicationStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily", scheduleTime: day(1), startedAt: day(1), endedAt: nil, refillDueAt: nil)

        let vm = makeVM()
        vm.load()
        vm.filter = .medication

        XCTAssertEqual(vm.filtered.map(\.kind), [.medication])
    }

    func testDueSoonReturnsUpcomingNextDuesSortedAscendingWithinHorizon() throws {
        let now = day(1_000)
        let inDays: (Int) -> Date = { now.addingTimeInterval(Double($0) * 86_400) }
        _ = try vaccinationStore.create(vaccineName: "DHPP", administeredAt: now, nextDueAt: inDays(20), lotNumber: nil, administeredBy: nil)
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
            vaccinationStore: vaccinationStore,
            vetVisitStore: vetVisitStore,
            medicationStore: medicationStore,
            doseLogStore: DoseLogStore(context: context),
            healthMarkerStore: healthMarkerStore,
            symptomEpisodeStore: symptomEpisodeStore,
            symptomEntryStore: SymptomEntryStore(context: context),
            recommendationStore: VetRecommendationStore(context: context),
            reminderScheduler: reminderScheduler,
            dueScheduler: dueScheduler,
            cadenceMonths: 6
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
        let vax = try vaccinationStore.create(vaccineName: "Rabies", administeredAt: day(1),
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
}
