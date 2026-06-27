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
}
