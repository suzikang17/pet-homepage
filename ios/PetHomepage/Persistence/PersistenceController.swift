// ios/PetHomepage/Persistence/PersistenceController.swift
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    /// Load the managed object model exactly once. `NSPersistentContainer(name:)` reloads the
    /// compiled model from the bundle on every call; with two live models, `+[Entity entity]`
    /// can't disambiguate the NSManagedObject subclass and inserts crash ("Multiple
    /// NSEntityDescriptions claim 'Pet'"). Sharing one model instance avoids that — and is the
    /// recommended pattern when several Core Data stacks coexist (e.g. across the test suite).
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "PetHomepage", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load Core Data model 'PetHomepage'")
        }
        return model
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        if inMemory {
            // Plain container with a throwaway store — no CloudKit in tests.
            container = NSPersistentContainer(name: "PetHomepage", managedObjectModel: Self.model)
            // Each test stack gets its OWN store file. Every in-memory container previously
            // shared the "/dev/null" URL, so concurrently-alive stacks (one per test class)
            // merged each other's change notifications through the shared model and
            // intermittently crashed Core Data's change processing ("attempt to insert nil"
            // inside NSManagedObjectContextObjectsDidChangeNotification). A unique temp-dir
            // SQLite file isolates them while keeping SQLite's exact fetch semantics — an
            // NSInMemoryStoreType store does NOT (its predicate/sort behavior differs).
            let description = NSPersistentStoreDescription(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PetHomepageTests-\(UUID().uuidString).sqlite"))
            container.persistentStoreDescriptions = [description]
        } else {
            container = NSPersistentCloudKitContainer(name: "PetHomepage", managedObjectModel: Self.model)
            if let description = container.persistentStoreDescriptions.first {
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Copies the legacy `startedAt` into `nextReminderAt` for any medication that lacks one.
    ///
    /// `startedAt` never meant what its name says — it held the next reminder date all along —
    /// so v2 introduces an honestly-named attribute and this carries the values across. Both
    /// fields exist because CloudKit's schema is append-only: the old one can never be removed,
    /// only abandoned.
    ///
    /// Deliberately NOT guarded by a one-time flag, unlike the walk backfill. It is keyed on
    /// `nextReminderAt == nil`, so it is idempotent AND it keeps working for records that arrive
    /// later from a device still running the old build — a run-once flag would strand those.
    @discardableResult
    static func backfillNextReminderAt(in context: NSManagedObjectContext) -> Int {
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "nextReminderAt == nil")
        guard let stale = try? context.fetch(request), !stale.isEmpty else { return 0 }
        for medication in stale {
            medication.nextReminderAt = medication.startedAt
        }
        try? context.save()
        return stale.count
    }
}
