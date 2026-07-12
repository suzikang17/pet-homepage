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
/// Implementation notes: unit tests execute inside the host app, which has already opened
/// the real store with CloudKit mirroring — opening that same file again is illegal
/// ("another instance actively syncing in this process"). So this builds a scratch
/// container: the app's already-loaded model (never load a second copy — ambiguous-entity
/// crashes) against a throwaway store URL. Schema init only needs the model, not the data.
final class CloudKitSchemaInitializer: XCTestCase {
    func testPushDevelopmentSchema() throws {
        let env = ProcessInfo.processInfo.environment
        // Skips on ordinary CI runs; the dedicated cloudkit-schema workflow opts in explicitly.
        try XCTSkipIf(env["CI"] != nil && env["CK_SCHEMA_FORCE"] == nil,
                      "Schema push runs only on a developer machine or the schema workflow")

        let model = Pet.entity().managedObjectModel
        let container = NSPersistentCloudKitContainer(name: "PetHomepage",
                                                      managedObjectModel: model)
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ck-schema-init-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: scratchURL)
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.pet.homepage")
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Scratch store failed to load: \(String(describing: loadError))")

        do {
            try container.initializeCloudKitSchema(options: [])
            print("✅ CloudKit Development schema pushed for iCloud.pet.homepage — now deploy to Production in the CloudKit Console")
        } catch {
            XCTFail("""
            ❌ CloudKit schema push FAILED: \(error)
            If this mentions authentication: sign Xcode into the team Apple ID \
            (Xcode → Settings → Accounts) and re-run.
            """)
        }
    }
}
