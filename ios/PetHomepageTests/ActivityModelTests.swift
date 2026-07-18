// ios/PetHomepageTests/ActivityModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityModelTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
    }

    func testActivityTypePersists() throws {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = "Bath"
        type.category = .care
        type.iconName = "shower"
        type.defaultIntervalDays = 30
        type.sortOrder = 0
        type.isArchived = false

        try context.save()

        let fetched = try context.fetch(ActivityType.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.category, .care)
    }

    func testCategoryAccessorRoundTripsAndFallsBack() throws {
        let type = ActivityType(context: context)
        type.category = .health
        XCTAssertEqual(type.categoryRaw, "health")
        type.categoryRaw = "bogus"
        XCTAssertEqual(type.category, .other)
    }
}
