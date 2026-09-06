// ios/PetHomepage/Features/Timeline/LogStreamView.swift
import SwiftUI

/// One date-sorted stream of every record, with type filters. Tapping a row opens that record's
/// existing editor.
///
/// This is the Schedule tab's **Log** subtab. It used to be half of `TimelineView`, sharing a tab
/// with the photo grid behind a Stream/Photos picker — the two shared a data source, not a
/// question. The log now sits beside Today and Upcoming, which is the question it actually
/// answers: what happened, what is happening, what is coming.
///
/// Deliberately has no `NavigationStack` and no header of its own: it renders inside the Schedule
/// tab's, and its add menu hangs off that header's "+" (see `RecordAddMenuItems`).
struct LogStreamView: View {
    @State private var model: TimelineViewModel
    @State private var editTarget: TimelineItem?
    @State private var medDetail: Medication?
    private let services: TimelineServices
    /// Bumped by the host after a record is added through the shared "+". That menu lives on the
    /// Schedule header, so the add sheet is presented above this view and its dismissal cannot
    /// reach the stream's own `onDismiss`.
    private let refreshToken: UUID

    init(services: TimelineServices, refreshToken: UUID = UUID()) {
        self.services = services
        self.refreshToken = refreshToken
        _model = State(initialValue: TimelineViewModel(
            medicationStore: services.medicationStore,
            logStore: services.logStore
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            chips
            content
        }
        .onAppear { model.load() }
        .onChange(of: refreshToken) { _, _ in model.load() }
        // Row thumbnails that weren't already cached are generated off the main thread and
        // filled in as they land. Keyed on `loadToken` so every reload — appear, sheet
        // dismiss, detail pop — starts a fresh pass and cancels the previous one.
        .task(id: model.loadToken) { await model.resolveThumbnails() }
        .sheet(item: $editTarget, onDismiss: { model.load() }) { editor(for: $0) }
        .navigationDestination(item: $medDetail) { med in
            MedicationDetailView(medication: med, services: services)
        }
        .onChange(of: medDetail) { _, new in if new == nil { model.load() } }
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
                .foregroundStyle(active ? Theme.onBrand : Theme.ink)
                .overlay(Capsule().stroke(Theme.ink.opacity(active ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timelineChip.\(title)")
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
            // No "NEXT <date>" badge: this is a record of what HAPPENED. Upcoming due dates live
            // on Home's "Upcoming reminders" and this tab's own Upcoming subtab, so a row here
            // never mixes the two.
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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

    private func tint(_ kind: TimelineKind) -> Color {
        switch kind {
        case .vaccine: .teal
        case .vet: .indigo
        case .medication: Theme.primaryDeep
        case .dose: Theme.primaryDeep
        case .marker: .pink
        case .symptom: .orange
        case .activity: .cyan
        case .diary: .brown
        case .routine: .mint
        }
    }
}
