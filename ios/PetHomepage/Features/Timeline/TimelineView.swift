// ios/PetHomepage/Features/Timeline/TimelineView.swift
import SwiftUI

/// Everything the Timeline needs to open each record type's existing editor/detail. Built once
/// in ContentView and shared (Home reuses the read stores for "due soon").
struct TimelineServices {
    let vaccinationStore: VaccinationStore
    let vetVisitStore: VetVisitStore
    let medicationStore: MedicationStore
    let doseLogStore: DoseLogStore
    let veterinarianStore: VeterinarianStore
    let healthMarkerStore: HealthMarkerStore
    let symptomEpisodeStore: SymptomEpisodeStore
    let symptomEntryStore: SymptomEntryStore
    let recommendationStore: VetRecommendationStore
    let reminderScheduler: MedicationReminderScheduler
    let dueScheduler: DueReminderScheduler
    let cadenceMonths: Int
}

/// One date-sorted stream of every record, with type filters. Tapping a row opens that record's
/// existing editor; the toolbar "+" adds any type. Replaces the separate Meds/Vaccines/Vet tabs.
struct TimelineView: View {
    @State private var model: TimelineViewModel
    @State private var editTarget: TimelineItem?
    @State private var addKind: TimelineKind?
    @State private var medDetail: Medication?
    private let services: TimelineServices

    init(services: TimelineServices) {
        self.services = services
        _model = State(initialValue: TimelineViewModel(
            vaccinationStore: services.vaccinationStore,
            vetVisitStore: services.vetVisitStore,
            medicationStore: services.medicationStore,
            healthMarkerStore: services.healthMarkerStore,
            symptomEpisodeStore: services.symptomEpisodeStore
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    HeroHeader(
                        title: "Timeline",
                        subtitle: model.filter?.label ?? "Everything",
                        systemImage: "calendar"
                    )
                    chips
                    content
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
    }

    private func chip(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Theme.primary : Color.white, in: Capsule())
                .foregroundStyle(active ? .white : Theme.ink)
                .overlay(Capsule().stroke(Theme.ink.opacity(active ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
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
                ForEach(model.filtered) { item in
                    Button {
                        switch item.reference {
                        case .medication(let m): medDetail = m   // medications get a detail page
                        case .marker: break                       // markers have no detail/editor
                        default: editTarget = item                // others open their editor sheet
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint(item.kind))
                .frame(width: 38, height: 38)
                .background(tint(item.kind).opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.date, format: .dateTime.month().day().year())
                    if let subtitle = item.subtitle { Text("· \(subtitle)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            if let due = item.nextDue {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("NEXT").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                    Text(due, format: .dateTime.month().day()).font(.caption.weight(.bold)).foregroundStyle(Theme.primary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Floating add button — bottom-trailing so it's in easy thumb reach.
    private var addButton: some View {
        Menu {
            Button { addKind = .vaccine } label: { Label("Vaccine", systemImage: "syringe") }
            Button { addKind = .vet } label: { Label("Vet visit", systemImage: "stethoscope") }
            Button { addKind = .medication } label: { Label("Medication", systemImage: "pills") }
            Button { addKind = .marker } label: { Label("Health marker", systemImage: "chart.xyaxis.line") }
            Button { addKind = .symptom } label: { Label("Symptom", systemImage: "waveform.path.ecg") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(0.35), radius: 12, y: 5)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 24)
    }



    @ViewBuilder
    private func editor(for item: TimelineItem) -> some View {
        switch item.reference {
        case .vaccine(let v):
            VaccinationEditView(store: services.vaccinationStore, dueScheduler: services.dueScheduler,
                                veterinarianStore: services.veterinarianStore, editing: v)
        case .vet(let v):
            VetVisitDetailView(visit: v, recommendationStore: services.recommendationStore)
        case .medication(let m):
            MedicationEditView(store: services.medicationStore, reminderScheduler: services.reminderScheduler,
                               veterinarianStore: services.veterinarianStore, editing: m)
        case .symptom(let ep):
            EpisodeDetailView(episode: ep, episodeStore: services.symptomEpisodeStore, entryStore: services.symptomEntryStore)
        case .marker:
            EmptyView()
        }
    }

    @ViewBuilder
    private func addEditor(for kind: TimelineKind) -> some View {
        switch kind {
        case .vaccine:
            VaccinationEditView(store: services.vaccinationStore, dueScheduler: services.dueScheduler,
                                veterinarianStore: services.veterinarianStore, editing: nil)
        case .vet:
            VetVisitEditView(store: services.vetVisitStore, dueScheduler: services.dueScheduler,
                             cadenceMonths: services.cadenceMonths,
                             veterinarianStore: services.veterinarianStore, editing: nil)
        case .medication:
            MedicationEditView(store: services.medicationStore, reminderScheduler: services.reminderScheduler,
                               veterinarianStore: services.veterinarianStore, editing: nil)
        case .marker:
            MarkerEditView(store: services.healthMarkerStore)
        case .symptom:
            EpisodeStartView(store: services.symptomEpisodeStore)
        }
    }

    private func tint(_ kind: TimelineKind) -> Color {
        switch kind {
        case .vaccine: .teal
        case .vet: .indigo
        case .medication: Theme.primary
        case .marker: .pink
        case .symptom: .orange
        }
    }
}
