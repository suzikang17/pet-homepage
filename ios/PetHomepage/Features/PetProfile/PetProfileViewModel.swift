// ios/PetHomepage/Features/PetProfile/PetProfileViewModel.swift
import Foundation
import Observation

@Observable
final class PetProfileViewModel {
    var name: String = ""
    var species: String = "dog"
    var photoData: Data?
    var isSaved: Bool = false

    private let store: PetStore

    init(store: PetStore) {
        self.store = store
        if let pet = try? store.currentPet() {
            name = pet.name
            species = pet.species
            photoData = pet.photoData
            isSaved = true
        }
    }

    /// Re-read name/species/photo from the store (e.g. species edited on the Health tab).
    func reload() {
        guard let pet = try? store.currentPet() else { return }
        name = pet.name
        species = pet.species
        photoData = pet.photoData
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
