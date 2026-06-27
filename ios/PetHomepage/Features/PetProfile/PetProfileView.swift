// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import SwiftUI

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false
    @State private var showUpload = false
    @State private var dueSoon: [TimelineItem] = []

    private let settings: SettingsViewModel?
    private let extractionService: ExtractionService?
    private let ingestionService: RecordIngestionService?
    private let timelineServices: TimelineServices?

    init(store: PetStore,
         settings: SettingsViewModel? = nil,
         extractionService: ExtractionService? = nil,
         ingestionService: RecordIngestionService? = nil,
         timelineServices: TimelineServices? = nil) {
        _model = State(initialValue: PetProfileViewModel(store: store))
        self.settings = settings
        self.extractionService = extractionService
        self.ingestionService = ingestionService
        self.timelineServices = timelineServices
    }

    private func refreshDueSoon() {
        guard let s = timelineServices else { return }
        let vm = TimelineViewModel(
            vaccinationStore: s.vaccinationStore,
            vetVisitStore: s.vetVisitStore,
            medicationStore: s.medicationStore,
            healthMarkerStore: s.healthMarkerStore,
            symptomEpisodeStore: s.symptomEpisodeStore
        )
        vm.load()
        dueSoon = vm.dueSoon(within: 30)
    }

    private var canScan: Bool { extractionService != nil && ingestionService != nil }

    /// Persist profile edits silently (no Save button) once there's a name.
    private func autosave() {
        guard !model.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? model.save()
    }

    var body: some View {
        NavigationStack {
            BrandScreen {
                HeroHeader(
                    title: model.name.isEmpty ? "Your pet" : model.name,
                    subtitle: "Home",
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

                if !dueSoon.isEmpty {
                    dueSoonCard.padding(.horizontal, 18)
                }

                if canScan {
                    Button { showUpload = true } label: { scanCard }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                }
            }
            .onChange(of: model.name) { _, _ in autosave() }
            .onChange(of: model.species) { _, _ in autosave() }
            .sheet(isPresented: $showSettings) {
                if let settings { SettingsView(model: settings) }
            }
            .sheet(isPresented: $showUpload, onDismiss: refreshDueSoon) {
                if let extractionService, let ingestionService {
                    RecordUploadView(extractionService: extractionService, ingestionService: ingestionService)
                }
            }
            .onAppear(perform: refreshDueSoon)
        }
    }

    private var dueSoonCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Due soon").font(Theme.headline()).foregroundStyle(Theme.ink)
                ForEach(dueSoon.prefix(4)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.kind.systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 30, height: 30)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(item.title).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        if let due = item.nextDue {
                            Text(due, format: .dateTime.month().day())
                                .font(.caption.weight(.bold)).foregroundStyle(Theme.primary)
                        }
                    }
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
