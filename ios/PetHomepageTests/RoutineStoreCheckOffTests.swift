// ios/PetHomepageTests/RoutineStoreCheckOffTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreCheckOffTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private var logStore: LogStore!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
    }

    func testCheckOffWritesRoutineLogEntryWithCopiedFields() throws {
        let task = try store.createTask(name: "Morning walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let now = Date()
        let entry = try store.checkOff(task, on: today, now: now)
        XCTAssertEqual(entry.kind, .routine)
        XCTAssertEqual(entry.title, "Morning walk") // copied on — template edits never rewrite it
        XCTAssertEqual(entry.routineLineageID, task.lineageID)
        XCTAssertEqual(entry.performedAt, now) // today's check-off stamps the actual moment
        XCTAssertEqual(entry.pet?.name, "Sandy")

        let slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertTrue(slot.isCompleted)
        XCTAssertEqual(slot.completion?.id, entry.id)
    }

    func testPastDayCheckOffStampsScheduledTime() throws {
        let task = try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                                        hour: 18, minute: 30, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: day(-2))
        let comps = calendar.dateComponents([.hour, .minute], from: entry.performedAt)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertTrue(calendar.isDate(entry.performedAt, inSameDayAs: day(-2)))
        XCTAssertTrue(try XCTUnwrap(try store.slots(for: day(-2)).first).isCompleted)
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: today).first).isCompleted)
    }

    func testCompletionSurvivesTemplateEdit() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        let successor = try store.editTask(task, name: "Long walk", category: .play,
                                           iconName: "figure.walk", hour: 9, minute: 0,
                                           weekdayMask: Weekdays.all)
        XCTAssertEqual(entry.title, "Walk") // history frozen
        // The completion still overlays today's slot (lineage is shared).
        let slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertEqual(slot.task.id, successor.id)
        XCTAssertTrue(slot.isCompleted)
    }

    func testUncheckDeletesEntryAndItsPhotos() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        try logStore.addPhoto(to: entry, imageData: Data([0xFF]))
        try store.uncheck(entry)
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: today).first).isCompleted)
        XCTAssertEqual(try context.fetch(Photo.fetchRequest()).count, 0) // cascade
        XCTAssertEqual(try logStore.allEntries().count, 0)
    }

    func testPhotoAttachesThroughExistingLogStoreAPI() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        try logStore.addPhoto(to: entry, imageData: Data([0x01, 0x02]))
        XCTAssertEqual(entry.photoArray.count, 1)
    }
}
