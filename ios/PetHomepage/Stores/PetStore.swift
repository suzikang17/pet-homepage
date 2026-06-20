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
}
