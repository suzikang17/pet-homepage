// ios/PetHomepage/Features/PetProfile/PetSwitcherView.swift
import SwiftUI
import UIKit

/// Sheet listing every pet with an avatar thumbnail (or paw placeholder), name, species, and a
/// checkmark on the active one. Tapping a row hands the pet back to the caller and dismisses —
/// switching itself (plus seeding + refresh) is the Home screen's job.
struct PetSwitcherView: View {
    let pets: [Pet]
    let activePetID: UUID?
    let onSelect: (Pet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(pets) { pet in
                Button {
                    onSelect(pet)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        avatarThumbnail(for: pet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(pet.species.capitalized).font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if pet.id == activePetID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.primary)
                                .accessibilityIdentifier("petSwitcherCheckmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("petSwitcherRow.\(pet.name)")
                // SwiftUI flattens a Button's children into one accessibility element, hiding
                // the checkmark image from XCUITest — expose active-ness as the row's value.
                .accessibilityValue(pet.id == activePetID ? "active" : "")
            }
            .navigationTitle("Switch pet")
            .navigationBarTitleDisplayMode(.inline)
            .brandSheet()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func avatarThumbnail(for pet: Pet) -> some View {
        if let data = pet.photoData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .background(Theme.primary.opacity(0.12), in: Circle())
        }
    }
}

/// Small add-pet form: name (required) + species (defaults "dog"). Self-contained sheet, hands
/// the trimmed values back through `onSave` — the parent decides how to create + activate + seed.
struct AddPetSheet: View {
    let onSave: (_ name: String, _ species: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species = "dog"

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        BrandFormSheet(
            title: "Add pet",
            systemImage: "pawprint.fill",
            confirmTitle: "Add",
            confirmDisabled: trimmedName.isEmpty,
            onCancel: { dismiss() },
            onConfirm: {
                let trimmedSpecies = species.trimmingCharacters(in: .whitespaces)
                onSave(trimmedName, trimmedSpecies.isEmpty ? "dog" : trimmedSpecies)
                dismiss()
            }
        ) {
            Section("Pet") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("addPetNameField")
                TextField("Species", text: $species)
            }
        }
    }
}
