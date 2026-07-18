// ios/PetHomepageTests/TimelineDayGroupTests.swift
import CoreData
import XCTest

@testable import PetHomepage

final class TimelineDayGroupTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var logStore: LogStore!
    private var model: TimelineViewModel!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context,
                                defaults: UserDefaults(suiteName: "timeline-\(UUID().uuidString)")!)
        _ = try petStore.ensurePet()
        logStore = LogStore(context: context, petStore: petStore)
        model = TimelineViewModel(medicationStore: MedicationStore(context: context, petStore: petStore),
                                  logStore: logStore)
    }

    override func tearDownWithError() throws {
        context = nil
        logStore = nil
        model = nil
    }

    func testItemsGroupIntoDaysNewestFirst() throws {
        let today = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        try logStore.createDiary(performedAt: today, note: "Today A")
        try logStore.createDiary(performedAt: today.addingTimeInterval(-3600), note: "Today B")
        try logStore.createDiary(performedAt: yesterday, note: "Yesterday")
        model.load()

        let groups = model.dayGroups(calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[1].items.count, 1)
        // Days descend; the flattened order matches the ungrouped stream.
        XCTAssertGreaterThan(groups[0].day, groups[1].day)
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), model.filtered.map(\.id))
    }

    func testGroupTitlesAreRelativeForTodayAndYesterday() throws {
        let now = Date()
        let today = TimelineDayGroup(day: calendar.startOfDay(for: now), items: [])
        XCTAssertEqual(today.title(calendar: calendar, now: now), "Today")

        let yesterdayDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let yesterday = TimelineDayGroup(day: calendar.startOfDay(for: yesterdayDate), items: [])
        XCTAssertEqual(yesterday.title(calendar: calendar, now: now), "Yesterday")

        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now))
        let olderGroup = TimelineDayGroup(day: calendar.startOfDay(for: older), items: [])
        let title = olderGroup.title(calendar: calendar, now: now)
        XCTAssertNotEqual(title, "Today")
        XCTAssertNotEqual(title, "Yesterday")
        XCTAssertFalse(title.isEmpty)
    }

    func testFilteringStillGroups() throws {
        try logStore.createDiary(performedAt: Date(), note: "Note")
        model.load()
        model.filter = .diary
        XCTAssertEqual(model.dayGroups(calendar: calendar).count, 1)
        model.filter = .vaccine
        XCTAssertTrue(model.dayGroups(calendar: calendar).isEmpty)
    }
}
