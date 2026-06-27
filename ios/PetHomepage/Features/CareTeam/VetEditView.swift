// ios/PetHomepage/Features/CareTeam/VetEditView.swift
import SwiftUI

struct VetEditView: View {
    @State private var model: VetEditViewModel
    @State private var showContacts = false
    @Environment(\.dismiss) private var dismiss

    init(store: VeterinarianStore, editing: Veterinarian?) {
        _model = State(initialValue: VetEditViewModel(store: store, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Veterinarian",
            systemImage: "stethoscope",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { try? model.save(); dismiss() }
        ) {
            Section {
                Button {
                    showContacts = true
                } label: {
                    Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section("Vet") {
                TextField("Name", text: $model.name)
                TextField("Clinic", text: $model.clinic)
            }
            Section("Contact") {
                TextField("Phone", text: $model.phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Website", text: $model.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }
            Section("Address") {
                TextField("Address", text: $model.address, axis: .vertical)
            }
            Section("Notes") {
                TextField("Notes", text: $model.notes, axis: .vertical)
            }
        }
        .sheet(isPresented: $showContacts) {
            ContactPicker(
                onPick: { model.apply(contact: $0); showContacts = false },
                onCancel: { showContacts = false }
            )
            .ignoresSafeArea()
        }
    }
}
