// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import SwiftUI

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false
    @State private var showUpload = false

    private let settings: SettingsViewModel?
    private let extractionService: ExtractionService?
    private let ingestionService: RecordIngestionService?

    init(store: PetStore,
         settings: SettingsViewModel? = nil,
         extractionService: ExtractionService? = nil,
         ingestionService: RecordIngestionService? = nil) {
        _model = State(initialValue: PetProfileViewModel(store: store))
        self.settings = settings
        self.extractionService = extractionService
        self.ingestionService = ingestionService
    }

    private var canScan: Bool { extractionService != nil && ingestionService != nil }

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

                if canScan {
                    Button { showUpload = true } label: { scanCard }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                }
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
                if let settings { SettingsView(model: settings) }
            }
            .sheet(isPresented: $showUpload) {
                if let extractionService, let ingestionService {
                    RecordUploadView(extractionService: extractionService, ingestionService: ingestionService)
                }
            }
        }
    }

    private var scanCard: some View {
        BrandCard {
            HStack(spacing: 14) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 46, height: 46)
                    .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan a record").font(Theme.headline()).foregroundStyle(Theme.ink)
                    Text("Upload a vet bill or vaccine record — AI files it")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
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
