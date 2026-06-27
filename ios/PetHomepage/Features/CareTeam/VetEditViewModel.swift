// ios/PetHomepage/Features/CareTeam/VetEditViewModel.swift
import Contacts
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

    /// Fill the form from a picked contact. Guards every field with `isKeyAvailable` so a
    /// partially-fetched contact never throws. Only overwrites a field when the contact has it.
    func apply(contact: CNContact) {
        if contact.isKeyAvailable(CNContactGivenNameKey) || contact.isKeyAvailable(CNContactFamilyNameKey) {
            let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { name = full }
        }
        if contact.isKeyAvailable(CNContactOrganizationNameKey), !contact.organizationName.isEmpty {
            if name.isEmpty { name = contact.organizationName }
            clinic = contact.organizationName
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey), let p = contact.phoneNumbers.first?.value.stringValue {
            phone = p
        }
        if contact.isKeyAvailable(CNContactEmailAddressesKey), let e = contact.emailAddresses.first?.value as String? {
            email = e
        }
        if contact.isKeyAvailable(CNContactUrlAddressesKey), let u = contact.urlAddresses.first?.value as String? {
            website = u
        }
        if contact.isKeyAvailable(CNContactPostalAddressesKey), let postal = contact.postalAddresses.first?.value {
            address = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        }
    }

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
