// ios/PetHomepageTests/CloudKitSchemaInitializer.swift
import CoreData
import XCTest

@testable import PetHomepage

/// Manual tool, not a test of app behavior: pushes the complete Core Data model into the
/// CloudKit **Development** schema (all entities, all attributes — no lazy per-record
/// creation). After a green run, deploy Development → Production in the CloudKit Console.
///
/// Runs automatically on any developer Mac (just run the test, no scheme setup); it
/// self-skips on CI (GitHub Actions sets CI=true) so automation never touches the schema.
/// initializeCloudKitSchema is idempotent — re-running is always safe.
///
/// Requirements on the Mac: Xcode signed into the team's Apple ID
/// (Xcode → Settings → Accounts) and network access. A real push takes several seconds;
/// an instant finish means it skipped or failed — read the message.
final class CloudKitSchemaInitializer: XCTestCase {
    func testPushDevelopmentSchema() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "Schema push runs only on a developer machine, never CI")
        let controller = PersistenceController()
        let container = try XCTUnwrap(
            controller.container as? NSPersistentCloudKitContainer,
            "Expected the real CloudKit-backed container")
        do {
            try container.initializeCloudKitSchema(options: [])
            print("✅ CloudKit Development schema pushed for iCloud.pet.homepage — now deploy to Production in the CloudKit Console")
        } catch {
            XCTFail("""
            ❌ CloudKit schema push FAILED: \(error)
            Usual causes: Xcode not signed into the team Apple ID (Xcode → Settings → \
            Accounts), or no network. Fix and re-run this test.
            """)
        }
    }
}
