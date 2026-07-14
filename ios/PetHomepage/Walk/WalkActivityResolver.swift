// ios/PetHomepage/Walk/WalkActivityResolver.swift
import CoreData
import Foundation

/// Resolves which ActivityType a detected walk logs as, without ever requiring the user to
/// pick one: their explicit choice if set, else an existing walk-named type, else one created
/// on the spot. Detection must never be silently disarmed by an unmade choice.
enum WalkActivityResolver {
    @discardableResult
    static func resolve(context: NSManagedObjectContext,
                        home: HomeLocationStore = HomeLocationStore(),
                        defaults: UserDefaults = .standard) -> UUID? {
        let petStore = PetStore(context: context, defaults: defaults)
        let store = ActivityStore(context: context, petStore: petStore)
        let types = (try? store.types()) ?? []

        // 1. The user's explicit pick, while it still exists.
        if let chosen = home.defaultActivityTypeID, types.contains(where: { $0.id == chosen }) {
            return chosen
        }
        // 2. An existing walk-named type.
        if let walk = types.first(where: { $0.name.localizedCaseInsensitiveContains("walk") }) {
            home.defaultActivityTypeID = walk.id
            return walk.id
        }
        // 3. Nothing suitable — create one so detection has somewhere to log.
        guard let created = try? store.createType(name: "Walk", category: .training,
                                                  iconName: "figure.walk",
                                                  defaultIntervalDays: 0) else { return nil }
        home.defaultActivityTypeID = created.id
        return created.id
    }
}
