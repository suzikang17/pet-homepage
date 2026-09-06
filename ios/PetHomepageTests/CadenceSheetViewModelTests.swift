// ios/PetHomepageTests/CadenceSheetViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

/// The sheet a cadence tile now opens. What matters here is that every mutation it exposes
/// repairs the cadence behind it — a history you can edit but that silently desynchronises the
/// reminders is worse than no history at all.
@MainActor
final class CadenceSheetViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var medStore: MedicationStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore, calendar: calendarValue)
        calendar = calendarValue
        now = date(8, 16)
    }

    private var calendarValue: Calendar { Calendar(identifier: .gregorian) }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendarValue.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func makeCatalogue() -> CadenceCatalogueViewModel {
        let fixed = now!
        return CadenceCatalogueViewModel(
            medicationStore: medStore,
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: { fixed }),
            dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()),
            calendar: calendar,
            now: { fixed })
    }

    private func makeServices() -> TimelineServices {
        let fixed = now!
        return TimelineServices(
            medicationStore: medStore,
            veterinarianStore: VeterinarianStore(context: context, petStore: petStore),
            diaryStore: DiaryStore(context: context, petStore: petStore),
            symptomEntryStore: SymptomEntryStore(context: context),
            recommendationStore: VetRecommendationStore(context: context),
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: { fixed }),
            dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()),
            cadenceMonths: 6,
            extractionService: nil,
            ingestionService: nil)
    }

    /// Builds the sheet for whichever tile is named, through the same catalogue the grid uses.
    private func makeSUT(for name: String) throws -> (CadenceSheetViewModel, CadenceCatalogueViewModel) {
        let catalogue = makeCatalogue()
        catalogue.load()
        let item = try XCTUnwrap(catalogue.items.first { $0.name == name })
        let fixed = now!
        let sut = try XCTUnwrap(CadenceSheetViewModel(item: item, catalogue: catalogue,
                                                      services: makeServices(),
                                                      calendar: calendar, now: { fixed }))
        return (sut, catalogue)
    }

    @discardableResult
    private func makeMed(_ name: String, nextDue: Date) throws -> Medication {
        let med = try medStore.create(drugName: name, dosage: "1 chew", frequency: "Monthly",
                                      scheduleTime: nextDue, nextReminderAt: nextDue,
                                      refillDueAt: nil)
        try context.save()
        return med
    }

    @discardableResult
    private func makeType(_ name: String, intervalDays: Int) throws -> ActivityType {
        try activityStore.createType(name: name, category: .care, iconName: "shower",
                                     defaultIntervalDays: intervalDays)
    }

    // MARK: - History

    func testHistoryIsNewestFirst() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        _ = try logStore.logDose(for: med, at: date(6, 1))
        _ = try logStore.logDose(for: med, at: date(8, 1))
        _ = try logStore.logDose(for: med, at: date(7, 1))

        let (sut, _) = try makeSUT(for: "Simparica")

        XCTAssertEqual(sut.entries.map(\.performedAt), [date(8, 1), date(7, 1), date(6, 1)])
    }

    func testActivityWithNoLogsStartsEmpty() throws {
        try makeType("Bath", intervalDays: 30)

        let (sut, _) = try makeSUT(for: "Bath")

        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.entries.count, 0)
    }

    // MARK: - Logging

    func testCommitLogsAtTheDraftDateRatherThanNow() async throws {
        try makeMed("Simparica", nextDue: date(8, 16))
        let (sut, _) = try makeSUT(for: "Simparica")

        sut.beginLogging()
        sut.draftDate = date(8, 14, 20)
        await sut.commit()

        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries.first?.performedAt, date(8, 14, 20))
        XCTAssertFalse(sut.isComposing)
    }

    func testCommitKeepsTheTypedNote() async throws {
        try makeMed("Simparica", nextDue: date(8, 16))
        let (sut, _) = try makeSUT(for: "Simparica")

        sut.beginLogging()
        sut.draftNote = "half dose, with food"
        await sut.commit()

        XCTAssertEqual(sut.entries.first?.note, "half dose, with food")
    }

    /// The failure this sheet exists to make visible: the same-day dedupe used to swallow the
    /// write and report nothing, so a tap on an already-logged tile looked like a dead button.
    func testSameDayLogIsReportedRatherThanSilentlySwallowed() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        _ = try logStore.logDose(for: med, at: date(8, 16, 7))
        let (sut, _) = try makeSUT(for: "Simparica")

        sut.beginLogging()
        sut.draftDate = date(8, 16, 18)
        await sut.commit()

        XCTAssertEqual(sut.entries.count, 1, "no second dose should be written")
        XCTAssertNotNil(sut.notice, "the user must be told why nothing was written")
        // …and the form is retargeted at the entry that blocked it, so the fix is one tap away.
        XCTAssertTrue(sut.isComposing)
    }

    func testLoggingRefreshesTheGridBehindTheSheet() async throws {
        try makeType("Bath", intervalDays: 30)
        let (sut, catalogue) = try makeSUT(for: "Bath")
        XCTAssertNil(catalogue.items.first { $0.name == "Bath" }?.lastDone)

        sut.beginLogging()
        await sut.commit()

        // A stale tile behind an open sheet is how the grid stops being trustworthy.
        XCTAssertEqual(catalogue.items.first { $0.name == "Bath" }?.lastDone, now)
    }

    // MARK: - Correcting an entry

    func testEditingADoseTimeMovesTheNextReminderWithIt() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        let (sut, _) = try makeSUT(for: "Simparica")
        sut.beginLogging()
        await sut.commit()
        let logged = try XCTUnwrap(sut.entries.first)

        sut.beginEditing(logged)
        sut.draftDate = date(8, 10)
        await sut.commit()

        XCTAssertEqual(sut.entries.first?.performedAt, date(8, 10))
        // Monthly cadence: the reminder must follow the corrected dose, not stay where the
        // original write put it.
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: med.nextReminder),
                       calendar.dateComponents([.year, .month, .day], from: date(9, 10)))
    }

    func testEditingAnActivityTimeRecomputesItsNextDue() async throws {
        try makeType("Bath", intervalDays: 30)
        let (sut, _) = try makeSUT(for: "Bath")
        sut.beginLogging()
        await sut.commit()
        let logged = try XCTUnwrap(sut.entries.first)

        sut.beginEditing(logged)
        sut.draftDate = date(8, 1)
        await sut.commit()

        XCTAssertEqual(sut.entries.first?.performedAt, date(8, 1))
        XCTAssertEqual(sut.entries.first?.nextDueAt, date(8, 31))
    }

    /// A walk carries an end time, and `LogStore.updateActivity` rejects an end before its start.
    /// Moving the start must carry the end with it rather than throwing into a `try?`.
    func testEditingAWalkTimePreservesItsDuration() async throws {
        let type = try makeType("Walk", intervalDays: 1)
        _ = try logStore.logActivity(type: type, performedAt: date(8, 15, 9),
                                     endedAt: date(8, 15, 10), note: nil, intervalDays: 1)
        let (sut, _) = try makeSUT(for: "Walk")
        let logged = try XCTUnwrap(sut.entries.first)

        sut.beginEditing(logged)
        sut.draftDate = date(8, 15, 14)
        await sut.commit()

        let edited = try XCTUnwrap(sut.entries.first)
        XCTAssertEqual(edited.performedAt, date(8, 15, 14))
        XCTAssertEqual(edited.endedAt, date(8, 15, 15), "the hour-long walk stays an hour long")
    }

    // MARK: - Deleting

    func testDeletingADoseMovesTheReminderBackToThePreviousOne() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        _ = try logStore.logDose(for: med, at: date(7, 10))
        let (sut, _) = try makeSUT(for: "Simparica")
        sut.beginLogging()
        sut.draftDate = date(8, 14)
        await sut.commit()
        let accidental = try XCTUnwrap(sut.entries.first)

        await sut.delete(accidental)

        XCTAssertEqual(sut.entries.map(\.performedAt), [date(7, 10)])
        // Without the repair the reminder would still point a month past the deleted dose.
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: med.nextReminder),
                       calendar.dateComponents([.year, .month, .day], from: date(8, 10)))
    }

    func testDeletingAnActivityLogRefreshesTheGrid() async throws {
        let type = try makeType("Bath", intervalDays: 30)
        _ = try logStore.logActivity(type: type, performedAt: date(8, 10), note: nil,
                                     intervalDays: 30)
        let (sut, catalogue) = try makeSUT(for: "Bath")
        let entry = try XCTUnwrap(sut.entries.first)

        await sut.delete(entry)

        XCTAssertTrue(sut.isEmpty)
        XCTAssertNil(catalogue.items.first { $0.name == "Bath" }?.lastDone)
    }

    // MARK: - Presentation

    func testLogButtonIsNamedAfterTheThingItLogs() throws {
        try makeMed("Simparica", nextDue: date(8, 16))
        try makeType("Bath", intervalDays: 30)

        let (med, _) = try makeSUT(for: "Simparica")
        let (bath, _) = try makeSUT(for: "Bath")

        XCTAssertEqual(med.logButtonTitle, "Log a dose")
        XCTAssertEqual(bath.logButtonTitle, "Log a bath")
    }
}
