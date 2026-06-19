// ios/PetHomepageTests/PersistenceControllerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryContainerLoadsAViewContext() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container.viewContext)
        XCTAssertTrue(controller.container.viewContext.automaticallyMergesChangesFromParent)
    }
}
