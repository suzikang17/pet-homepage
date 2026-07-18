// ios/PetHomepageTests/TimelineRoutineTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class TimelineRoutineTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var logStore: LogStore!
    private var routineStore: RoutineStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        routineStore = RoutineStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        logStore = nil
        routineStore = nil
    }

    func testRoutineEntriesAppearInTimelineWithRoutineKind() throws {
        let task = try routineStore.createTask(name: "Morning walk", category: .play,
                                               iconName: "figure.walk", hour: 8, minute: 0,
                                               weekdayMask: Weekdays.all)
        let entry = try routineStore.checkOff(task, on: Date())
        try logStore.addPhoto(to: entry, imageData: Data([0x01]))

        let model = TimelineViewModel(medicationStore: MedicationStore(context: context, petStore: petStore),
                                      logStore: logStore)
        model.load()
        let item = try XCTUnwrap(model.items.first { $0.kind == .routine })
        XCTAssertEqual(item.title, "Morning walk")
        XCTAssertEqual(item.subtitle, "1 photo")
        // The Routine chip filters to exactly these entries.
        model.filter = .routine
        XCTAssertEqual(model.filtered.count, 1)
    }

    func testRoutineEntriesExcludedFromDiaryQuery() throws {
        let task = try routineStore.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                               hour: 8, minute: 0, weekdayMask: Weekdays.all)
        try routineStore.checkOff(task, on: Date())
        XCTAssertEqual(try logStore.diaryEntries().count, 0)
        XCTAssertEqual(try logStore.routineEntries().count, 1)
    }
}
