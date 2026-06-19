// ios/PetHomepage/Features/PetProfile/PetProfileViewModel.swift
import Foundation
import Observation

@Observable
final class PetProfileViewModel {
    var name: String = ""
    var species: String = "dog"
    var isSaved: Bool = false

    private let store: PetStore

    init(store: PetStore) {
        self.store = store
        if let pet = try? store.currentPet() {
            name = pet.name
            species = pet.species
            isSaved = true
        }
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
