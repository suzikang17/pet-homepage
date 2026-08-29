// ios/PetHomepage/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var syncError: String?
    @State private var showPair = false
    @State private var petName = ""
    @State private var petSpecies = "dog"

    private let petStore: PetStore

    // "Scan a record" → /api/extract config (read by ContentView when building the service).
    @AppStorage("extractEndpoint") private var extractEndpoint = ""
    @AppStorage("extractSecret") private var extractSecret = ""

    init(model: SettingsViewModel, petStore: PetStore) {
        _model = State(initialValue: model)
        self.petStore = petStore
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HeroHeader(title: "Settings", subtitle: "Preferences", systemImage: "gearshape.fill")

                    BrandCard {
                        VStack(spacing: 0) {
                            FieldRow(label: "Name") {
                                TextField("e.g. Sandy", text: $petName)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(Theme.ink)
                                    .onChange(of: petName) { _, new in
                                        let trimmed = new.trimmingCharacters(in: .whitespaces)
                                        if !trimmed.isEmpty { try? petStore.setName(trimmed) }
                                    }
                            }
                            Divider().overlay(Theme.bg)
                            FieldRow(label: "Species") {
                                Picker("", selection: $petSpecies) {
                                    Text("🐶  Dog").tag("dog")
                                    Text("🐱  Cat").tag("cat")
                                    Text("🐾  Other").tag("other")
                                }
                                .labelsHidden().tint(Theme.primary)
                                .onChange(of: petSpecies) { _, new in try? petStore.setSpecies(new) }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .onAppear {
                        if let pet = try? petStore.currentPet() {
                            petName = pet.name
                            petSpecies = pet.species
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("Desktop mirror")
                            Toggle("Mirror to dashboard", isOn: $model.isMirroringEnabled)
                                .font(Theme.body().weight(.semibold))
                                .tint(Theme.primary)
                            Text(model.privacyNote)
                                .font(.footnote).foregroundStyle(Theme.inkSoft)

                            Button {
                                showPair = true
                            } label: {
                                Label("Pair a device", systemImage: "qrcode.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            Text("Scan the QR on your dashboard, or type the short code — no copy-paste.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)

                            DisclosureGroup("Set up manually") {
                              VStack(alignment: .leading, spacing: 14) {
                            field {
                                TextField("Deployment URL", text: $model.mirrorEndpoint,
                                          prompt: Text("https://…convex.site/mirror/push"))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                            field {
                                SecureField("Mirror token", text: $model.mirrorToken,
                                            prompt: Text("Paste token from dashboard"))
                            }
                            Text("Mint a token on the web dashboard, then paste it here with your deployment URL. The token is stored in the device Keychain.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                              }
                            }
                            .tint(Theme.primary)

                            Button("Sync now") {
                                Task {
                                    do { _ = try await model.syncNow() }
                                    catch { syncError = error.localizedDescription }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!model.isMirroringEnabled)

                            if let syncError {
                                Text(syncError).font(.footnote).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .sheet(isPresented: $showPair) {
                        PairDeviceView(service: URLSessionPairingService()) { token, endpoint in
                            model.applyPairing(token: token, endpoint: endpoint)
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("Walk detection")
                            NavigationLink {
                                WalkDetectionSettingsView()
                            } label: {
                                HStack {
                                    Label("Auto-detect walks", systemImage: "figure.walk.motion")
                                        .font(Theme.body().weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Text("Get a prompt when a walk starts and log it automatically when you're back home.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 18)

                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("Ideas")
                            NavigationLink {
                                IdeaListView(store: FileIdeaStore.documents(), screen: nil)
                            } label: {
                                HStack {
                                    Label("Idea scratchpad", systemImage: "lightbulb")
                                        .font(Theme.body().weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .accessibilityIdentifier("settings.ideas")
                            Text("Jot down improvements as you use the app — or just shake the phone from any screen.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 18)

                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("AI record extraction")
                            field {
                                TextField("Endpoint URL", text: $extractEndpoint,
                                          prompt: Text("https://…/api/extract"))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                            field {
                                SecureField("Extract secret", text: $extractSecret,
                                            prompt: Text("x-extract-secret"))
                            }
                            Text("Powers “Scan a record.” Point this at your deployed /api/extract and paste its EXTRACT_SECRET.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 18)

                    BrandCard {
                        VStack(alignment: .leading, spacing: 12) {
                            BrandCardTitle("Documents · iCloud Drive")
                            if model.documentRows.isEmpty {
                                Text("No documents yet. Uploaded records appear here.")
                                    .font(Theme.body()).foregroundStyle(Theme.inkSoft)
                            } else {
                                ForEach(model.documentRows) { row in
                                    documentRow(row)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDragIndicator(.visible)
            .onAppear { model.loadDocuments() }
        }
    }

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.body())
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func documentRow(_ row: DocumentRow) -> some View {
        if let url = try? model.shareURL(for: row) {
            ShareLink(item: url) {
                Label(row.reference.fileName, systemImage: "doc.fill").tint(Theme.primary)
            }
        } else {
            Label(row.reference.fileName, systemImage: "doc")
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

/// Small heavy uppercased title used at the top of a BrandCard.
struct BrandCardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSoft)
    }
}
