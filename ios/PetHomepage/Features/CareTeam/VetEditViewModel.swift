// ios/PetHomepage/Features/CareTeam/VetEditViewModel.swift
import Foundation
import Observation

@Observable
final class VetEditViewModel {
    var name = ""
    var clinic = ""
    var phone = ""
    var email = ""
    var address = ""
    var website = ""
    var notes = ""

    private let store: VeterinarianStore
    private let editing: Veterinarian?

    init(store: VeterinarianStore, editing: Veterinarian?) {
        self.store = store
        self.editing = editing
        if let v = editing {
            name = v.name
            clinic = v.clinic ?? ""
            phone = v.phone ?? ""
            email = v.email ?? ""
            address = v.address ?? ""
            website = v.website ?? ""
            notes = v.notes ?? ""
        }
    }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func opt(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    func save() throws {
        if let editing {
            try store.update(editing, name: name, clinic: opt(clinic), phone: opt(phone),
                             email: opt(email), address: opt(address), website: opt(website), notes: opt(notes))
        } else {
            try store.create(name: name, clinic: opt(clinic), phone: opt(phone),
                             email: opt(email), address: opt(address), website: opt(website), notes: opt(notes))
        }
    }
}
