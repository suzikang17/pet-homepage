// ios/PetHomepageTests/ActivityModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityModelTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testActivityTypeAndLogPersistAndRelate() throws {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = "Bath"
        type.category = .care
        type.iconName = "shower"
        type.defaultIntervalDays = 30
        type.sortOrder = 0
        type.isArchived = false

        let log = ActivityLog(context: context)
        log.id = UUID()
        log.performedAt = Date(timeIntervalSince1970: 1_000)
        log.intervalDays = 30
        log.nextDueAt = Date(timeIntervalSince1970: 1_000 + 30 * 86_400)
        log.activityType = type

        try context.save()

        let fetched = try context.fetch(ActivityType.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.category, .care)
        XCTAssertEqual((fetched.first?.logs as? Set<ActivityLog>)?.count, 1)
    }

    func testCategoryAccessorRoundTripsAndFallsBack() throws {
        let type = ActivityType(context: context)
        type.category = .health
        XCTAssertEqual(type.categoryRaw, "health")
        type.categoryRaw = "bogus"
        XCTAssertEqual(type.category, .other)
    }
}
