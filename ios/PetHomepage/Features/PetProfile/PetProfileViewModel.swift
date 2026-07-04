// ios/PetHomepage/Features/PetProfile/PetProfileViewModel.swift
import Foundation
import Observation

@Observable
final class PetProfileViewModel {
    var name: String = ""
    var species: String = "dog"
    var photoData: Data?
    var isSaved: Bool = false
    /// All pets (for the switcher sheet), reloaded alongside the active pet's fields.
    var pets: [Pet] = []
    /// The active pet's id, so the switcher can checkmark the right row.
    var activePetID: UUID?

    private let store: PetStore

    init(store: PetStore) {
        self.store = store
        if let pet = try? store.currentPet() {
            name = pet.name
            species = pet.species
            photoData = pet.photoData
            isSaved = true
            activePetID = pet.id
        }
        pets = (try? store.pets()) ?? []
    }

    /// Re-read name/species/photo/pets from the store (e.g. species edited on the Health tab,
    /// or after switching/adding a pet).
    func reload() {
        pets = (try? store.pets()) ?? []
        guard let pet = try? store.currentPet() else { return }
        name = pet.name
        species = pet.species
        photoData = pet.photoData
        activePetID = pet.id
    }

    /// Makes `pet` the active pet. Callers (Home) are responsible for reloading and refreshing
    /// dependent state, and for seeding starter activity types via `timelineServices` — that
    /// store is optional at the View layer (e.g. absent in previews), not something this
    /// PetStore-only ViewModel should assume exists.
    func switchTo(_ pet: Pet) {
        store.setActivePet(pet)
    }

    /// Creates a new pet and makes it active. Returns nil if the create failed.
    @discardableResult
    func addPet(name: String, species: String) -> Pet? {
        guard let pet = try? store.createPet(name: name, species: species) else { return nil }
        store.setActivePet(pet)
        return pet
    }

    /// Persist a new pet photo (or nil to clear). Creates the pet if needed.
    func setPhoto(_ data: Data?) {
        try? store.setPhoto(data, defaultName: name.isEmpty ? "Your pet" : name, defaultSpecies: species)
        photoData = data
    }

    func save() throws {
        if let pet = try store.currentPet() {
            try store.update(pet, name: name, species: species)
        } else {
            try store.createPet(name: name, species: species)
        }
        isSaved = true
    }
}
