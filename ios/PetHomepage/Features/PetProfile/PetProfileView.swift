// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import PhotosUI
import SwiftUI
import UIKit

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false
    @State private var showUpload = false
    @State private var showAddWeight = false
    @State private var showAddSymptom = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    // Dashboard data, refreshed on appear + after any add.
    @State private var upcoming: [TimelineItem] = []
    @State private var recent: [TimelineItem] = []
    @State private var activeMeds: [Medication] = []
    @State private var latestWeight: HealthMarker?
    @State private var nextVetVisit: Date?

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

    private var canScan: Bool { extractionService != nil && ingestionService != nil }

    var body: some View {
        NavigationStack {
            BrandScreen {
                HeroHeader(
                    title: model.name.isEmpty ? "Your pet" : model.name,
                    subtitle: "Home",
                    systemImage: speciesIcon,
                    avatar: avatarImage,
                    onTapAvatar: { showPhotoPicker = true },
                    onSettings: settings != nil ? { showSettings = true } : nil
                )

                petCard.padding(.horizontal, 18)

                if timelineServices != nil {
                    atAGlance
                    quickActions
                }

                if !upcoming.isEmpty {
                    upcomingCard.padding(.horizontal, 18)
                }
                if !recent.isEmpty {
                    recentCard.padding(.horizontal, 18)
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
            .sheet(isPresented: $showUpload, onDismiss: refresh) {
                if let extractionService, let ingestionService {
                    RecordUploadView(extractionService: extractionService, ingestionService: ingestionService)
                }
            }
            .sheet(isPresented: $showAddWeight, onDismiss: refresh) {
                if let s = timelineServices { MarkerEditView(store: s.healthMarkerStore) }
            }
            .sheet(isPresented: $showAddSymptom, onDismiss: refresh) {
                if let s = timelineServices { EpisodeStartView(store: s.symptomEpisodeStore) }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
            .onAppear(perform: refresh)
        }
    }

    private var avatarImage: Image? {
        guard let data = model.photoData, let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            // Downscale so we don't store a multi-MB original in Core Data / CloudKit.
            let avatar = image.preparingThumbnail(of: CGSize(width: 512, height: 512)) ?? image
            model.setPhoto(avatar.jpegData(compressionQuality: 0.85))
        }
    }

    // MARK: - Pet identity (auto-saving)

    private var petCard: some View {
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
    }

    // MARK: - At a glance

    private var atAGlance: some View {
        HStack(spacing: 12) {
            statTile(icon: "scalemass.fill", value: weightText, label: "Weight", tint: .pink)
            statTile(icon: "pills.fill", value: "\(activeMeds.count)",
                     label: activeMeds.count == 1 ? "Active med" : "Active meds", tint: Theme.primary)
            statTile(icon: "stethoscope", value: vetText, label: "Next vet", tint: .indigo)
        }
        .padding(.horizontal, 18)
    }

    private func statTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            if !activeMeds.isEmpty {
                Menu {
                    ForEach(activeMeds, id: \.id) { med in
                        Button(med.drugName) { logDose(med) }
                    }
                } label: {
                    quickTile("Log dose", "checkmark.circle.fill")
                }
            }
            Button { showAddWeight = true } label: { quickTile("Log weight", "scalemass") }
                .buttonStyle(.plain)
            Button { showAddSymptom = true } label: { quickTile("Symptom", "waveform.path.ecg") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private func quickTile(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Upcoming + Recent

    private var upcomingCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upcoming").font(Theme.headline()).foregroundStyle(Theme.ink)
                ForEach(upcoming.prefix(5)) { item in
                    miniRow(item, trailing: item.nextDue, tint: Theme.primary)
                }
            }
        }
    }

    private var recentCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent activity").font(Theme.headline()).foregroundStyle(Theme.ink)
                ForEach(recent) { item in
                    miniRow(item, trailing: item.date, tint: Theme.inkSoft)
                }
            }
        }
    }

    private func miniRow(_ item: TimelineItem, trailing: Date?, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(item.title).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing, format: .dateTime.month().day())
                    .font(.caption.weight(.semibold)).foregroundStyle(tint)
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

    // MARK: - Data + helpers

    private func refresh() {
        guard let s = timelineServices else { return }
        let vm = TimelineViewModel(
            vaccinationStore: s.vaccinationStore,
            vetVisitStore: s.vetVisitStore,
            medicationStore: s.medicationStore,
            healthMarkerStore: s.healthMarkerStore,
            symptomEpisodeStore: s.symptomEpisodeStore
        )
        vm.load()
        upcoming = vm.dueSoon(within: 60)
        recent = Array(vm.items.prefix(4))

        let meds = (try? s.medicationStore.medications()) ?? []
        activeMeds = meds.filter { $0.endedAt == nil || ($0.endedAt.map { $0 > Date() } ?? true) }
        latestWeight = (try? s.healthMarkerStore.series(of: .weight))?.last
        let visits = (try? s.vetVisitStore.visits()) ?? []
        nextVetVisit = visits.compactMap(\.nextVisitDate).filter { $0 >= Date() }.min()
    }

    private func logDose(_ med: Medication) {
        guard let s = timelineServices else { return }
        _ = try? s.doseLogStore.logDose(for: med, at: Date())
        refresh()
    }

    private func autosave() {
        guard !model.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? model.save()
    }

    private var weightText: String {
        guard let w = latestWeight else { return "—" }
        let v = w.value == w.value.rounded() ? String(Int(w.value)) : String(format: "%.1f", w.value)
        return w.unit.map { "\(v) \($0)" } ?? v
    }

    private var vetText: String {
        guard let d = nextVetVisit else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0
        return days <= 0 ? "Today" : "\(days)d"
    }

    private var speciesIcon: String {
        switch model.species {
        case "cat": "cat.fill"
        default: "pawprint.fill"
        }
    }
}
