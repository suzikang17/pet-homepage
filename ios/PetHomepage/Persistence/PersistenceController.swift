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
            // Plain container with an in-memory store — no CloudKit in tests.
            container = NSPersistentContainer(name: "PetHomepage", managedObjectModel: Self.model)
            // Each test stack gets its OWN store. Every in-memory container previously shared
            // the "/dev/null" URL, so concurrently-alive stacks (one per test class) merged
            // each other's change notifications through the shared model and intermittently
            // crashed Core Data's change processing ("attempt to insert nil" inside
            // NSManagedObjectContextObjectsDidChangeNotification).
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
                .appendingPathComponent(UUID().uuidString)
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
        // Merging from the parent coordinator matters only for the real (CloudKit-backed)
        // stack; on isolated in-memory test stores it just invites cross-stack churn.
        container.viewContext.automaticallyMergesChangesFromParent = !inMemory
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
