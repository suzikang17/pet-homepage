// ios/PetHomepage/Stores/ActivityStore.swift
import CoreData

/// CRUD for user-defined activity types, scoped to the single current pet (v1). Mirrors
/// HealthMarkerStore / VaccinationStore. Logged occurrences live in LogStore now; this store
/// only owns the ActivityType definitions.
final class ActivityStore {
    let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    // MARK: - Types

    @discardableResult
    func createType(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int,
                    reminderHour: Int = 9,
                    reminderMinute: Int = 0) throws -> ActivityType {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        type.reminderHour = Int64(reminderHour)
        type.reminderMinute = Int64(reminderMinute)
        type.sortOrder = Int64(try types(includeArchived: true).count)
        type.isArchived = false
        type.pet = try petStore.ensurePet()
        try context.save()
        return type
    }

    /// Activity types for the current pet, sorted by category then sortOrder then name.
    func types(includeArchived: Bool = false) throws -> [ActivityType] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = ActivityType.fetchRequest()
        request.predicate = includeArchived
            ? NSPredicate(format: "pet == %@", pet)
            : NSPredicate(format: "pet == %@ AND isArchived == NO", pet)
        let all = try context.fetch(request)
        return all.sorted { lhs, rhs in
            if lhs.category.displayName != rhs.category.displayName {
                return lhs.category.displayName < rhs.category.displayName
            }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    func updateType(_ type: ActivityType,
                    name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int,
                    reminderHour: Int = 9,
                    reminderMinute: Int = 0) throws {
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        type.reminderHour = Int64(reminderHour)
        type.reminderMinute = Int64(reminderMinute)
        try context.save()
    }

    func archiveType(_ type: ActivityType) throws {
        type.isArchived = true
        try context.save()
    }

    // MARK: - Seeding

    /// The starter set of editable activity types, pre-seeded so logging works with zero setup.
    static let defaultSeeds: [(name: String, category: ActivityCategory, iconName: String, intervalDays: Int)] = [
        ("Bath", .care, "shower", 30),
        ("Nail trim", .care, "scissors", 21),
        ("Teeth brushing", .care, "mouth", 1),
        ("Brushing", .care, "comb", 7),
        ("Grooming", .care, "dog", 42),
        ("Flea & tick", .health, "ladybug", 30),
        ("Deworming", .health, "pills", 90),
    ]

    /// Seeds any default types that don't already exist (by case-insensitive name). Idempotent,
    /// and a no-op when there is no current pet. Safe to call every time the Activities UI appears:
    /// because it de-dupes by name against ALL existing types (including ones synced in from another
    /// device via CloudKit), it won't double-seed once the cloud import has settled.
    func seedDefaultsIfNeeded() throws {
        guard (try petStore.currentPet()) != nil else { return }
        let existingNames = Set(try types(includeArchived: true).map { $0.name.lowercased() })
        for seed in Self.defaultSeeds where !existingNames.contains(seed.name.lowercased()) {
            try createType(name: seed.name,
                           category: seed.category,
                           iconName: seed.iconName,
                           defaultIntervalDays: seed.intervalDays)
        }
    }
}
