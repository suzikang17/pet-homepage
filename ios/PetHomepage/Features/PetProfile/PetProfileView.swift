// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import PhotosUI
import SwiftUI
import UIKit

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false
    @State private var showAddWeight = false
    @State private var showAddSymptom = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var cropTarget: PickedImage?

    // Dashboard data, refreshed on appear + after any add.
    @State private var upcoming: [TimelineItem] = []
    @State private var recent: [TimelineItem] = []
    @State private var activeMeds: [Medication] = []
    @State private var latestWeight: HealthMarker?
    @State private var nextVetVisit: Date?

    private let petStore: PetStore
    private let settings: SettingsViewModel?
    private let timelineServices: TimelineServices?

    init(store: PetStore,
         settings: SettingsViewModel? = nil,
         timelineServices: TimelineServices? = nil) {
        _model = State(initialValue: PetProfileViewModel(store: store))
        self.petStore = store
        self.settings = settings
        self.timelineServices = timelineServices
    }

    var body: some View {
        NavigationStack {
            BrandScreen {
                HeroHeader(
                    title: "Home",
                    subtitle: model.name.isEmpty ? "Your pet" : model.name,
                    systemImage: speciesIcon,
                    backgroundImage: avatarImage,
                    onTapAvatar: { showPhotoPicker = true },
                    onSettings: settings != nil ? { showSettings = true } : nil
                )

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

            }
            .sheet(isPresented: $showSettings) {
                if let settings { SettingsView(model: settings, petStore: petStore) }
            }
            .sheet(isPresented: $showAddWeight, onDismiss: refresh) {
                if let s = timelineServices { MarkerEditView(store: s.healthMarkerStore) }
            }
            .sheet(isPresented: $showAddSymptom, onDismiss: refresh) {
                if let s = timelineServices { EpisodeStartView(store: s.symptomEpisodeStore) }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
            .sheet(item: $cropTarget) { picked in
                PhotoCropView(image: picked.image) { model.setPhoto($0) }
            }
            .onAppear { model.reload(); refresh() }
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
            // Hand off to the cropper to choose the focus; it saves the framed result.
            await MainActor.run { cropTarget = PickedImage(image: image) }
        }
    }

    private struct PickedImage: Identifiable {
        let id = UUID()
        let image: UIImage
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


    // MARK: - Data + helpers

    private func refresh() {
        guard let s = timelineServices else { return }
        let vm = TimelineViewModel(
            medicationStore: s.medicationStore,
            healthMarkerStore: s.healthMarkerStore,
            symptomEpisodeStore: s.symptomEpisodeStore,
            logStore: s.logStore
        )
        vm.load()
        upcoming = vm.dueSoon(within: 60)
        recent = Array(vm.items.prefix(4))

        let meds = (try? s.medicationStore.medications()) ?? []
        activeMeds = meds.filter { $0.endedAt == nil || ($0.endedAt.map { $0 > Date() } ?? true) }
        latestWeight = (try? s.healthMarkerStore.series(of: .weight))?.last
        let visits = (try? s.logStore.vetVisits()) ?? []
        nextVetVisit = visits.compactMap(\.nextDueAt).filter { $0 >= Date() }.min()
    }

    private func logDose(_ med: Medication) {
        guard let s = timelineServices else { return }
        _ = try? s.logStore.logDose(for: med, at: Date())
        refresh()
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
