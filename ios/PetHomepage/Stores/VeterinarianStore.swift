// ios/PetHomepage/Stores/VeterinarianStore.swift
import CoreData

/// CRUD for the pet's care team. Veterinarians are pet-scoped and can be attached to vet visits,
/// vaccinations, and medications.
final class VeterinarianStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func create(name: String, clinic: String? = nil, phone: String? = nil, email: String? = nil,
                address: String? = nil, website: String? = nil, notes: String? = nil) throws -> Veterinarian {
        let vet = Veterinarian(context: context)
        vet.id = UUID()
        vet.name = name
        vet.clinic = clinic
        vet.phone = phone
        vet.email = email
        vet.address = address
        vet.website = website
        vet.notes = notes
        vet.pet = try petStore.ensurePet()
        try context.save()
        return vet
    }

    /// All veterinarians for the current pet, sorted by name.
    func veterinarians() throws -> [Veterinarian] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = Veterinarian.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    func update(_ vet: Veterinarian, name: String, clinic: String?, phone: String?, email: String?,
                address: String?, website: String?, notes: String?) throws {
        vet.name = name
        vet.clinic = clinic
        vet.phone = phone
        vet.email = email
        vet.address = address
        vet.website = website
        vet.notes = notes
        try context.save()
    }

    func delete(_ vet: Veterinarian) throws {
        context.delete(vet)
        try context.save()
    }
}
