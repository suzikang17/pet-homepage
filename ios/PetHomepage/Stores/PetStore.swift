// ios/PetHomepage/Stores/PetStore.swift
import CoreData

final class PetStore {
    /// The shared managed-object context. Read-only to collaborators (e.g. SnapshotBuilder),
    /// which need it for fetches the typed stores don't expose.
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
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

    /// v1 is single-pet: return the one pet if it exists.
    func currentPet() throws -> Pet? {
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
