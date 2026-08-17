// ios/PetHomepageTests/LogStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class LogStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: LogStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = LogStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testCreateDiaryHasNoReferenceAndIsDiaryKind() throws {
        let e = try store.createDiary(performedAt: Date(timeIntervalSince1970: 0), note: "  walk in park  ")
        XCTAssertEqual(e.kind, .diary)
        XCTAssertEqual(e.note, "walk in park")
        XCTAssertEqual(e.pet?.name, "Sandy")
        XCTAssertEqual(try store.diaryEntries().count, 1)
        XCTAssertEqual(try store.activityLogs().count, 0)
    }

    func testAllPhotosReturnsAttachedDiaryPhotosNewestFirst() throws {
        let entry = try store.createDiary(performedAt: Date(timeIntervalSince1970: 0), note: "walk")
        let older = try store.addPhoto(to: entry, imageData: Data([0x1]), createdAt: Date(timeIntervalSince1970: 100))
        let newer = try store.addPhoto(to: entry, imageData: Data([0x2]), createdAt: Date(timeIntervalSince1970: 200))

        let photos = try store.allPhotos()
        XCTAssertEqual(photos.count, 2)
        XCTAssertEqual(photos.first, newer)
        XCTAssertEqual(photos.last, older)
    }

    func testLogActivityStampsNextDueAndIsActivityKind() throws {
        let type = ActivityType(context: context)
        type.id = UUID(); type.name = "Bath"; type.category = .care; type.iconName = "shower"
        type.defaultIntervalDays = 30; type.sortOrder = 0; type.isArchived = false; type.pet = try petStore.ensurePet()
        let start = Date(timeIntervalSince1970: 0)
        let e = try store.logActivity(type: type, performedAt: start, note: nil, intervalDays: 30)
        XCTAssertEqual(e.kind, .activity)
        XCTAssertEqual(e.nextDueAt, Calendar.current.date(byAdding: .day, value: 30, to: start))
        XCTAssertEqual(try store.activityLogs().count, 1)
        XCTAssertEqual(try store.latestLog(of: type)?.id, e.id)
        XCTAssertEqual(try store.diaryEntries().count, 0)
    }

    func testLogDoseIsDoseKindAndQueryable() throws {
        let med = Medication(context: context)
        med.id = UUID(); med.drugName = "Apoquel"; med.dosage = "16mg"; med.frequency = "daily"; med.nextReminder = Date()
        med.pet = try petStore.ensurePet()
        try store.logDose(for: med, at: Date(timeIntervalSince1970: 100), note: nil)
        try store.logDose(for: med, at: Date(timeIntervalSince1970: 300), note: nil)
        XCTAssertEqual(try store.doses(for: med).count, 2)
        XCTAssertEqual(try store.doseCount(for: med), 2)
        XCTAssertEqual(try store.lastDose(for: med), Date(timeIntervalSince1970: 300))
        XCTAssertEqual(try store.doses(for: med).first?.kind, .dose)
        // dose logs are neither diary nor activity
        XCTAssertEqual(try store.diaryEntries().count, 0)
        XCTAssertEqual(try store.activityLogs().count, 0)
    }

    func testAllEntriesNewestFirstAndDeleteRemoves() throws {
        let a = try store.createDiary(performedAt: Date(timeIntervalSince1970: 100), note: "a")
        _ = try store.createDiary(performedAt: Date(timeIntervalSince1970: 300), note: "b")
        XCTAssertEqual(try store.allEntries().map(\.note), ["b", "a"])
        try store.delete(a)
        XCTAssertEqual(try store.allEntries().count, 1)
    }

    func testEmptyWithoutPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let s = LogStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try s.allEntries().count, 0)
        XCTAssertEqual(try s.diaryEntries().count, 0)
    }

    func testBackfillKindsIfNeededCorrectsEntriesButLeavesDiaryAlone() throws {
        let med = Medication(context: context)
        med.id = UUID(); med.drugName = "Apoquel"; med.dosage = "16mg"; med.frequency = "daily"; med.nextReminder = Date()
        med.pet = try petStore.ensurePet()

        let type = ActivityType(context: context)
        type.id = UUID(); type.name = "Bath"; type.category = .care; type.iconName = "shower"
        type.defaultIntervalDays = 30; type.sortOrder = 0; type.isArchived = false; type.pet = try petStore.ensurePet()

        let dose = try store.logDose(for: med, at: Date(timeIntervalSince1970: 100), note: nil)
        let activity = try store.logActivity(type: type, performedAt: Date(timeIntervalSince1970: 200), note: nil, intervalDays: 0)
        let diary = try store.createDiary(performedAt: Date(timeIntervalSince1970: 300), note: "just a note")

        // Simulate pre-kindRaw rows: every entry still claims the default "diary" even though
        // dose/activity have their defining refs set.
        dose.kindRaw = "diary"
        activity.kindRaw = "diary"
        diary.kindRaw = "diary"
        try context.save()

        try store.backfillKindsIfNeeded()

        XCTAssertEqual(dose.kind, .dose)
        XCTAssertEqual(activity.kind, .activity)
        XCTAssertEqual(diary.kind, .diary)
    }
}
