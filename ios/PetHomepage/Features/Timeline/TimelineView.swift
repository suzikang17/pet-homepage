// ios/PetHomepage/Features/Timeline/TimelineView.swift
import SwiftUI
import UIKit

/// Everything the Timeline needs to open each record type's existing editor/detail. Built once
/// in ContentView and shared (Home reuses the read stores for "due soon").
struct TimelineServices {
    let medicationStore: MedicationStore
    let veterinarianStore: VeterinarianStore
    let diaryStore: DiaryStore
    let symptomEntryStore: SymptomEntryStore
    let recommendationStore: VetRecommendationStore
    let activityStore: ActivityStore
    let logStore: LogStore
    let reminderScheduler: MedicationReminderScheduler
    let dueScheduler: DueReminderScheduler
    let cadenceMonths: Int
    /// AI record scanning (PDF/photo → extraction → ingestion). Optional: nil disables the
    /// "Scan a record" menu entry (e.g. when the extract endpoint isn't configured).
    let extractionService: ExtractionService?
    let ingestionService: RecordIngestionService?
}

/// One date-sorted stream of every record, with type filters. Tapping a row opens that record's
/// existing editor; the toolbar "+" adds any type. Replaces the separate Meds/Vaccines/Vet tabs.
struct TimelineView: View {
    /// Stream is the date-sorted record list (with type chips); Photos is the all-photos grid
    /// ported from the retired Diary tab.
    enum ViewMode: String, CaseIterable, Identifiable {
        case stream = "Stream"
        case photos = "Photos"
        var id: String { rawValue }
    }

    @State private var model: TimelineViewModel
    @State private var viewMode: ViewMode = .stream
    @State private var editTarget: TimelineItem?
    @State private var addKind: TimelineKind?
    @State private var medDetail: Medication?
    @State private var showActivityTypes = false
    @State private var showScan = false
    private let services: TimelineServices
    /// Opens the capture flow (camera / stub / library fallback), owned by ContentView.
    private let onCapture: (() -> Void)?
    /// Opens the photo-library picker directly, owned by ContentView.
    private let onImport: (() -> Void)?

    init(services: TimelineServices, onCapture: (() -> Void)? = nil,
         onImport: (() -> Void)? = nil) {
        self.services = services
        self.onCapture = onCapture
        self.onImport = onImport
        _model = State(initialValue: TimelineViewModel(
            medicationStore: services.medicationStore,
            logStore: services.logStore
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    HeroHeader(
                        title: "Timeline",
                        subtitle: viewMode == .stream ? (model.filter?.label ?? "Everything") : ViewMode.photos.rawValue,
                        systemImage: "calendar",
                        onSettings: { showActivityTypes = true },
                        settingsSymbol: "slider.horizontal.3"
                    )
                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .accessibilityIdentifier("timelineViewModePicker")

                    if viewMode == .stream {
                        chips
                        content
                    } else {
                        photoGrid
                    }
                }
                addButton
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { model.load() }
            .sheet(item: $editTarget, onDismiss: { model.load() }) { editor(for: $0) }
            .sheet(item: $addKind, onDismiss: { model.load() }) { addEditor(for: $0) }
            .navigationDestination(item: $medDetail) { med in
                MedicationDetailView(medication: med, services: services)
            }
            .onChange(of: medDetail) { _, new in if new == nil { model.load() } }
            .sheet(isPresented: $showActivityTypes) {
                NavigationStack {
                    ActivityTypesView(store: services.activityStore)
                }
            }
            .sheet(isPresented: $showScan, onDismiss: { model.load() }) {
                if let ex = services.extractionService, let ing = services.ingestionService {
                    RecordUploadView(extractionService: ex, ingestionService: ing)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: model.filter == nil) { model.filter = nil }
                ForEach(TimelineKind.allCases) { kind in
                    chip(kind.label, active: model.filter == kind) { model.filter = kind }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier("timelineChipsStrip")
    }

    private func chip(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Theme.primary : Theme.card, in: Capsule())
                .foregroundStyle(active ? .white : Theme.ink)
                .overlay(Capsule().stroke(Theme.ink.opacity(active ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timelineChip.\(title)")
    }

    @ViewBuilder
    private var photoGrid: some View {
        if model.photos.isEmpty {
            ContentUnavailableView(
                "No photos yet",
                systemImage: "photo.on.rectangle",
                description: Text("Photos from diary entries and records show up here.")
            )
        } else {
            PhotoGalleryView(photos: model.photos)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.filtered.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "calendar.badge.plus",
                description: Text("Tap + to add a record, or scan one from Home.")
            )
        } else {
            List {
                ForEach(model.dayGroups()) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                switch item.reference {
                                case .medication(let m): medDetail = m // medications get a detail page
                                case .marker: break                    // markers have no detail/editor
                                default: editTarget = item             // others open their editor sheet
                                }
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.bg)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await model.delete(item, using: services) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.title())
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(spacing: 12) {
            if let url = item.thumbnailURL {
                PhotoThumbnail(url: url, side: 44, cornerRadius: 10)
            }
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint(item.kind))
                .frame(width: 38, height: 38)
                .background(tint(item.kind).opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 5) {
                    // The day lives in the section header — rows carry the time of day.
                    Text(item.date, format: .dateTime.hour().minute())
                    if let subtitle = item.subtitle { Text("· \(subtitle)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            // No "NEXT <date>" badge: the Timeline is a record of what HAPPENED. Upcoming due
            // dates live on Home's "Upcoming reminders" and the Schedule tab's Upcoming subtab,
            // so a row here never mixes the two.
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Floating add button — bottom-trailing so it's in easy thumb reach.
    private var addButton: some View {
        Menu {
            if let onCapture {
                Button { onCapture() } label: { Label("Take photo", systemImage: "camera") }
            }
            if let onImport {
                Button { onImport() } label: {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                }
            }
            if services.extractionService != nil && services.ingestionService != nil {
                Button { showScan = true } label: { Label("Scan a record", systemImage: "sparkles") }
            }
            if onCapture != nil || onImport != nil
                || (services.extractionService != nil && services.ingestionService != nil) {
                Divider()
            }
            Button { addKind = .diary } label: { Label("Note", systemImage: "square.and.pencil") }
            Button { addKind = .activity } label: { Label("Activity", systemImage: "shower") }
            Button { addKind = .medication } label: { Label("Medication", systemImage: "pills") }
            Button { addKind = .symptom } label: { Label("Symptom", systemImage: "waveform.path.ecg") }
            // Low-frequency record types grouped under a submenu to keep the menu short.
            Menu {
                Button { addKind = .vaccine } label: { Label("Vaccine", systemImage: "syringe") }
                Button { addKind = .vet } label: { Label("Vet visit", systemImage: "stethoscope") }
                Button { addKind = .marker } label: { Label("Health marker", systemImage: "chart.xyaxis.line") }
            } label: {
                Label("Health record", systemImage: "cross.case")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(0.35), radius: 12, y: 5)
        }
        .accessibilityIdentifier("timelineAddButton")
        .padding(.trailing, 22)
        .padding(.bottom, 24)
    }



    @ViewBuilder
    private func editor(for item: TimelineItem) -> some View {
        switch item.reference {
        case .vaccine(let v):
            VaccinationEditView(logStore: services.logStore, dueScheduler: services.dueScheduler,
                                veterinarianStore: services.veterinarianStore, editing: v)
        case .vet(let v):
            VetVisitDetailView(visit: v, recommendationStore: services.recommendationStore,
                               logStore: services.logStore)
        case .medication(let m):
            MedicationEditView(store: services.medicationStore, reminderScheduler: services.reminderScheduler,
                               veterinarianStore: services.veterinarianStore, editing: m)
        case .dose(let d):
            // A dose has no editor of its own; its medication's detail screen owns the dose
            // history (and its swipe-to-delete). Nothing to show if the medication is gone.
            if let med = d.medication {
                NavigationStack { MedicationDetailView(medication: med, services: services) }
            } else {
                EmptyView()
            }
        case .symptom(let ep):
            EpisodeDetailView(episode: ep, logStore: services.logStore, entryStore: services.symptomEntryStore)
        case .marker:
            EmptyView()
        case .activity(let log):
            ActivityLogEditView(logStore: services.logStore, store: services.activityStore,
                                dueScheduler: services.dueScheduler, editing: log)
        case .diary(let entry):
            DiaryEntryEditView(logStore: services.logStore, editing: entry)
        case .routine(let entry):
            // Routine completions reuse the diary editor for note/photo edits: updateDiary only
            // touches performedAt/note, never kindRaw, so the entry stays kind routine.
            DiaryEntryEditView(logStore: services.logStore, editing: entry)
        }
    }

    @ViewBuilder
    private func addEditor(for kind: TimelineKind) -> some View {
        switch kind {
        // A dose belongs to a medication, so it is logged from a Home tile, a notification, or
        // the medication's own screen — never created standalone from the Timeline's add menu.
        case .dose:
            EmptyView()
        case .vaccine:
            VaccinationEditView(logStore: services.logStore, dueScheduler: services.dueScheduler,
                                veterinarianStore: services.veterinarianStore, editing: nil)
        case .vet:
            VetVisitEditView(logStore: services.logStore, dueScheduler: services.dueScheduler,
                             cadenceMonths: services.cadenceMonths,
                             veterinarianStore: services.veterinarianStore, editing: nil)
        case .medication:
            MedicationEditView(store: services.medicationStore, reminderScheduler: services.reminderScheduler,
                               veterinarianStore: services.veterinarianStore, editing: nil)
        case .marker:
            MarkerEditView(logStore: services.logStore)
        case .symptom:
            EpisodeStartView(store: services.logStore)
        case .activity:
            ActivityLogEditView(logStore: services.logStore, store: services.activityStore,
                                dueScheduler: services.dueScheduler, editing: nil)
        case .diary:
            DiaryEntryEditView(logStore: services.logStore, editing: nil)
        case .routine:
            // Routine completions are created by checking off tasks in the Schedule tab —
            // never from the Timeline's add menu (which has no Routine entry).
            EmptyView()
        }
    }

    private func tint(_ kind: TimelineKind) -> Color {
        switch kind {
        case .vaccine: .teal
        case .vet: .indigo
        case .medication: Theme.primary
        case .dose: Theme.primary
        case .marker: .pink
        case .symptom: .orange
        case .activity: .cyan
        case .diary: .brown
        case .routine: .mint
        }
    }
}
