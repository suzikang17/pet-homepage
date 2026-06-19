// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import SwiftUI

struct PetProfileView: View {
    @State private var model: PetProfileViewModel

    init(store: PetStore) {
        _model = State(initialValue: PetProfileViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pet") {
                    TextField("Name", text: $model.name)
                    Picker("Species", selection: $model.species) {
                        Text("Dog").tag("dog")
                        Text("Cat").tag("cat")
                        Text("Other").tag("other")
                    }
                }
                Section {
                    Button("Save") { try? model.save() }
                        .disabled(model.name.isEmpty)
                }
            }
            .navigationTitle("Profile")
        }
    }
}
