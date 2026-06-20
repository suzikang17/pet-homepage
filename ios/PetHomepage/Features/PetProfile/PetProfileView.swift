// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import SwiftUI

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false

    private let settings: SettingsViewModel?

    init(store: PetStore, settings: SettingsViewModel? = nil) {
        _model = State(initialValue: PetProfileViewModel(store: store))
        self.settings = settings
    }

    var body: some View {
        NavigationStack {
            BrandScreen {
                HeroHeader(
                    title: model.name.isEmpty ? "Your pet" : model.name,
                    subtitle: "Profile",
                    systemImage: speciesIcon,
                    onSettings: settings != nil ? { showSettings = true } : nil
                )

                BrandCard {
                    VStack(spacing: 0) {
                        FieldRow(label: "Name") {
                            TextField("e.g. Sandy", text: $model.name)
                                .font(Theme.body())
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.ink)
                        }
                        Divider().overlay(Theme.bg)
                        FieldRow(label: "Species") {
                            Picker("", selection: $model.species) {
                                Text("🐶  Dog").tag("dog")
                                Text("🐱  Cat").tag("cat")
                                Text("🐾  Other").tag("other")
                            }
                            .labelsHidden()
                            .tint(Theme.primary)
                        }
                    }
                }
                .padding(.horizontal, 18)
            } action: {
                Button {
                    try? model.save()
                } label: {
                    Text(model.isSaved ? "Saved" : "Save profile")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.name.isEmpty)
            }
            .sheet(isPresented: $showSettings) {
                if let settings {
                    SettingsView(model: settings)
                }
            }
        }
    }

    private var speciesIcon: String {
        switch model.species {
        case "cat": "cat.fill"
        default: "pawprint.fill"
        }
    }
}
