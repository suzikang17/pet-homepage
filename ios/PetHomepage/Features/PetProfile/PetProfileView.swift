// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import PhotosUI
import SwiftUI
import UIKit

struct PetProfileView: View {
    @State private var model: PetProfileViewModel
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var cropTarget: PickedImage?
    @State private var showAvatarActions = false
    @State private var showPetSwitcher = false
    @State private var showAddPet = false
    @State private var catalogue: CadenceCatalogueViewModel?
    /// "View all" destination — resolves to the medication or care-activity detail screen.
    @State private var detailTarget: CadenceItem?

    // Dashboard data, refreshed on appear + after any add.
    @State private var recent: [TimelineItem] = []

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
                    onTapAvatar: { showAvatarActions = true },
                    onSettings: settings != nil ? { showSettings = true } : nil
                )

                if let catalogue, !catalogue.items.isEmpty {
                    cadenceGrid(catalogue).padding(.horizontal, 18)
                }
                if let catalogue, !catalogue.upcoming.isEmpty {
                    upcomingCard(catalogue.upcoming).padding(.horizontal, 18)
                }
                if !recent.isEmpty {
                    recentCard.padding(.horizontal, 18)
                }

            }
            .navigationDestination(item: $detailTarget) { item in
                if let s = timelineServices {
                    // A tile is a shortcut; this is the record behind it. Medications already had
                    // such a screen, so each source routes to its own rather than being forced
                    // through one shape — dosage and prescriber have no activity equivalent.
                    switch item.source {
                    case .medication(let objectID):
                        if let obj = try? s.medicationStore.context.existingObject(with: objectID),
                           let med = obj as? Medication {
                            MedicationDetailView(medication: med, services: s)
                        }
                    case .activityType(let objectID):
                        if let obj = try? s.activityStore.context.existingObject(with: objectID),
                           let type = obj as? ActivityType {
                            CareActivityDetailView(type: type, services: s)
                        }
                    }
                }
            }
            .onChange(of: detailTarget) { _, new in if new == nil { refresh() } }
            .sheet(isPresented: $showSettings) {
                if let settings { SettingsView(model: settings, petStore: petStore) }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
            .sheet(item: $cropTarget) { picked in
                PhotoCropView(image: picked.image) { model.setPhoto($0) }
            }
            // The avatar tap is one affordance with three intents. A confirmationDialog (rather
            // than turning the tap into a Menu) keeps HeroHeader's `onTapAvatar: (() -> Void)?`
            // API untouched — it's the only call site, but this is still the smaller diff.
            .confirmationDialog("Pet", isPresented: $showAvatarActions, titleVisibility: .hidden) {
                Button("Switch pet…") { showPetSwitcher = true }
                    .accessibilityIdentifier("avatarMenu.switchPet")
                Button("Add pet…") { showAddPet = true }
                    .accessibilityIdentifier("avatarMenu.addPet")
                Button("Change photo…") { showPhotoPicker = true }
                    .accessibilityIdentifier("avatarMenu.changePhoto")
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPetSwitcher) {
                PetSwitcherView(pets: model.pets, activePetID: model.activePetID) { pet in
                    switchTo(pet)
                }
            }
            .sheet(isPresented: $showAddPet) {
                AddPetSheet { name, species in
                    addPet(name: name, species: species)
                }
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


    // MARK: - Cadence catalogue

    /// A tile per recurring thing. Replaces the old Upcoming card, which was built from the
    /// Timeline stream and so could only show things already logged at least once — and whose
    /// `due >= now` filter hid overdue items entirely.
    private func cadenceGrid(_ model: CadenceCatalogueViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Care routine").font(Theme.headline()).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                // Long-press is invisible without saying so, and it is the only route to a tile's
                // history, its cadence editor, and backdated logging.
                Text("Hold a tile for details")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.items) { item in
                    CadenceTile(
                        item: item,
                        now: Date(),
                        onTap: { Task { await model.log(item); refresh() } },
                        // Long-press opens the record rather than a bare date picker: that screen
                        // already has the full log form (date, note, and for activities an end
                        // time), the cadence editor, and the history with per-entry delete — i.e.
                        // everything backdating and bookkeeping actually need.
                        onLongPress: { detailTarget = item })
                }
            }
            if let logged = model.lastLogged {
                confirmationStrip(logged.item, model: model)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.lastLogged?.entry.id)
    }

    /// Sits inline under the grid rather than floating over content: the tile animating IS the
    /// confirmation, and this only carries the two things the animation can't — the way back out
    /// of a stray tap, and the way into the full record.
    private func confirmationStrip(_ item: CadenceItem,
                                   model: CadenceCatalogueViewModel) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
            Text("\(item.name) logged").font(.subheadline).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("Undo") { Task { await model.undoLastLog(); refresh() } }
                .font(.subheadline.weight(.semibold))
            Button("View all") { detailTarget = item }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: model.lastLogged?.entry.id) {
            // Auto-dismiss, but only this strip: a newer log replaces the id and restarts the
            // timer rather than letting a stale one cancel the new strip.
            try? await Task.sleep(for: .seconds(4))
            model.dismissConfirmation()
        }
    }

    // MARK: - Upcoming reminders

    /// Everything dated, most urgent first. Separate from "Recent activity" because they answer
    /// opposite questions — what is coming versus what already happened — and the two were
    /// previously conflated into one card that showed future reminder dates under the heading
    /// "Recent activity".
    private func upcomingCard(_ reminders: [UpcomingReminder]) -> some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upcoming reminders").font(Theme.headline()).foregroundStyle(Theme.ink)
                ForEach(reminders.prefix(6)) { reminder in
                    let state = reminder.dueState(now: Date())
                    HStack(spacing: 10) {
                        Image(systemName: reminder.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(state.badgeTint)
                            .frame(width: 18)
                        Text(reminder.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(state.badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(state.badgeTint)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(reminder.name), \(state.badgeText)")
                }
            }
        }
    }

    // MARK: - Recent

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
            logStore: s.logStore
        )
        vm.load()
        // "Recent activity" means things that HAPPENED. Two exclusions, both load-bearing:
        //
        // `.medication` rows are prescription RECORDS, not events — they have no event date, so
        // TimelineItem borrows `startedAt`, which is the next-reminder date and therefore in the
        // FUTURE. Sorted newest-first, every active medication outranked real history and filled
        // this card with next-reminder dates instead of anything the user had done.
        //
        // The future-date filter then catches the same class of thing generally, so a record that
        // borrows a due date can never masquerade as recent history again.
        let now = Date()
        recent = Array(vm.items.lazy.filter { $0.kind != .medication && $0.date <= now }.prefix(4))

        let model = catalogue ?? CadenceCatalogueViewModel(
            medicationStore: s.medicationStore,
            activityStore: s.activityStore,
            logStore: s.logStore,
            reminderScheduler: s.reminderScheduler,
            dueScheduler: s.dueScheduler)
        model.load()
        catalogue = model
    }


    /// Switches the active pet, seeds its starter activity types (idempotent), then reloads the
    /// hero + dashboard slices so they reflect the newly active pet.
    private func switchTo(_ pet: Pet) {
        model.switchTo(pet)
        seedActivityDefaultsIfPossible()
        model.reload()
        refresh()
    }

    /// Creates + activates a new pet, seeds its starter activity types, then reloads.
    private func addPet(name: String, species: String) {
        model.addPet(name: name, species: species)
        seedActivityDefaultsIfPossible()
        model.reload()
        refresh()
    }

    /// `timelineServices` can be nil (e.g. previews), so seeding is best-effort.
    private func seedActivityDefaultsIfPossible() {
        guard let s = timelineServices else { return }
        try? s.activityStore.seedDefaultsIfNeeded()
    }




    private var speciesIcon: String {
        switch model.species {
        case "cat": "cat.fill"
        default: "pawprint.fill"
        }
    }
}

