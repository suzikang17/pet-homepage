// ios/PetHomepageTests/CloudKitSchemaInitializer.swift
import CoreData
import XCTest

@testable import PetHomepage

/// Manual tool, not a test of app behavior: pushes the complete Core Data model into the
/// CloudKit **Development** schema (all entities, all attributes — no lazy per-record
/// creation). Run it from Xcode whenever the model changes, then deploy Development →
/// Production in the CloudKit Console.
///
/// How to run: Product → Scheme → Edit Scheme… → Test → Arguments → Environment Variables →
/// add CK_SCHEMA_INIT = 1, then run just this test (⌘U or the diamond in the gutter).
/// Without that variable it self-skips, so CI never touches the schema.
final class CloudKitSchemaInitializer: XCTestCase {
    func testPushDevelopmentSchema() throws {
        guard ProcessInfo.processInfo.environment["CK_SCHEMA_INIT"] == "1" else {
            throw XCTSkip("Schema push is manual-only: set CK_SCHEMA_INIT=1 in the test scheme.")
        }
        let controller = PersistenceController()
        let container = try XCTUnwrap(
            controller.container as? NSPersistentCloudKitContainer,
            "Expected the real CloudKit-backed container")
        try container.initializeCloudKitSchema(options: [])
    }
}
