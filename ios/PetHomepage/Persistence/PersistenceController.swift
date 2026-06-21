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
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
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
}
