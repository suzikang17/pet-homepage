// ios/PetHomepage/Stores/PetStore.swift
import CoreData

final class PetStore {
    /// The shared managed-object context. Read-only to collaborators (e.g. SnapshotBuilder),
    /// which need it for fetches the typed stores don't expose.
    let context: NSManagedObjectContext
    /// Where the active-pet selection is persisted. Injectable so tests can use a scratch
    /// suite instead of polluting `.standard`.
    private let defaults: UserDefaults

    /// UserDefaults key for the active pet's `id.uuidString`. Per-device (not synced) —
    /// deliberate v1 simplification (see multi-pet design doc).
    private static let activePetIDKey = "activePetID"

    init(context: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    @discardableResult
    func createPet(name: String, species: String) throws -> Pet {
        let pet = Pet(context: context)
        pet.id = UUID()
        pet.name = name
        pet.species = species
        try context.save()
        return pet
    }

    /// All pets, sorted by name.
    func pets() throws -> [Pet] {
        let request = Pet.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    /// Persists `pet` as the active pet (per-device). Every store scopes its reads/writes
    /// through `currentPet()`, so this is the whole switcher mechanism.
    func setActivePet(_ pet: Pet) {
        defaults.set(pet.id.uuidString, forKey: Self.activePetIDKey)
    }

    /// The active pet: the one matching the persisted `activePetID` if it still exists,
    /// else the first pet (existing v1 behavior; also the fallback for a missing/unknown/
    /// deleted id, e.g. pre-multi-pet installs that never wrote the key).
    func currentPet() throws -> Pet? {
        if let idString = defaults.string(forKey: Self.activePetIDKey), let id = UUID(uuidString: idString) {
            let request = Pet.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let pet = try context.fetch(request).first {
                return pet
            }
        }
        let request = Pet.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// The current pet, creating a default one if none exists yet. Use this when CREATING a
    /// record so it always attaches to a pet — records added before the user names their pet
    /// would otherwise be orphaned (pet == nil) and never appear in any list.
    @discardableResult
    func ensurePet(defaultName: String = "Your pet", defaultSpecies: String = "dog") throws -> Pet {
        try currentPet() ?? createPet(name: defaultName, species: defaultSpecies)
    }

    func update(_ pet: Pet, name: String, species: String) throws {
        pet.name = name
        pet.species = species
        try context.save()
    }

    /// Set (or clear, with nil) the current pet's photo. Creates a pet if none exists yet.
    @discardableResult
    func setPhoto(_ data: Data?, defaultName: String = "Your pet", defaultSpecies: String = "dog") throws -> Pet {
        let pet = try currentPet() ?? createPet(name: defaultName, species: defaultSpecies)
        pet.photoData = data
        try context.save()
        return pet
    }

    /// Set the current pet's name. Creates a pet if none exists yet.
    @discardableResult
    func setName(_ name: String, defaultSpecies: String = "dog") throws -> Pet {
        let pet = try currentPet() ?? createPet(name: name, species: defaultSpecies)
        pet.name = name
        try context.save()
        return pet
    }

    /// Set the current pet's species. Creates a pet if none exists yet.
    @discardableResult
    func setSpecies(_ species: String, defaultName: String = "Your pet") throws -> Pet {
        let pet = try currentPet() ?? createPet(name: defaultName, species: species)
        pet.species = species
        try context.save()
        return pet
    }
}
