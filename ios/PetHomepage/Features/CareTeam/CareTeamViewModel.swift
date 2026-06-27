// ios/PetHomepage/Features/CareTeam/CareTeamViewModel.swift
import Foundation
import Observation

@Observable
final class CareTeamViewModel {
    var vets: [Veterinarian] = []

    private let store: VeterinarianStore

    init(store: VeterinarianStore) {
        self.store = store
        load()
    }

    func load() {
        vets = (try? store.veterinarians()) ?? []
    }

    func delete(_ vet: Veterinarian) {
        try? store.delete(vet)
        load()
    }
}
