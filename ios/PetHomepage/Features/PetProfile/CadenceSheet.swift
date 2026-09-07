// ios/PetHomepage/Features/PetProfile/CadenceSheet.swift
import SwiftUI

/// What a cadence tile opens: the recurring thing itself, everything it has been logged as, and
/// a confirmed way to add, correct or remove one of those.
///
/// This exists because tapping a tile used to WRITE. The tile is a two-column grid of
/// similar-looking cards, so the most reachable gesture was also the destructive one, and the
/// only way back out was a four-second Undo strip. A tap now reads; logging is a button in here
/// (or a deliberate long-press on the tile), and every entry can be re-timed or deleted.
///
/// One view over both sources. Dosage and prescriber have no activity equivalent, so anything
/// source-specific stays behind `MedicationDetailView` / `CareActivityDetailView` — pushed from
/// the row at the bottom, inside this sheet's own navigation stack.
struct CadenceSheet: View {
    @State private var model: CadenceSheetViewModel
    @State private var pendingDelete: LogEntry?
    @Environment(\.dismiss) private var dismiss
    private let services: TimelineServices

    /// Fails when the tile's record no longer resolves, in which case the caller shows nothing.
    /// `@MainActor` because `CadenceSheetViewModel` is, and this builds one.
    @MainActor
    init?(item: CadenceItem, catalogue: CadenceCatalogueViewModel, services: TimelineServices) {
        guard let model = CadenceSheetViewModel(item: item, catalogue: catalogue,
                                                services: services) else { return nil }
        _model = State(initialValue: model)
        self.services = services
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 12, trailing: 4))

                logSection

                Section(model.historyTitle) {
                    if model.isEmpty {
                        Text("Nothing logged yet.").foregroundStyle(Theme.inkSoft)
                    } else {
                        ForEach(model.entries, id: \.id) { entry in
                            entryRow(entry)
                        }
                    }
                }

                Section {
                    NavigationLink("Open full record") { fullRecord }
                }
            }
            .brandSheet()
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // A stray tap used to cost a database write; now the worst it costs is this sheet. The
        // confirmation is only on the genuinely destructive action left in here.
        .confirmationDialog("Delete this entry?", isPresented: deleteDialogBinding,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = pendingDelete {
                    Task { await model.delete(entry); pendingDelete = nil }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if let entry = pendingDelete {
                Text(Self.stamp(entry.performedAt))
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let url = model.item.dailyPhotoURL {
                PhotoThumbnail(url: url, side: 46, cornerRadius: 12)
            } else {
                Image(systemName: model.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryDeep)
                    .frame(width: 46, height: 46)
                    .background(Theme.primary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                if let subtitle = model.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Text(model.dueState.badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.dueState.badgeTint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logging

    @ViewBuilder
    private var logSection: some View {
        if model.isComposing {
            Section {
                DatePicker("When", selection: $model.draftDate)
                TextField("Note (optional)", text: $model.draftNote, axis: .vertical)
                Button {
                    Task { await model.commit() }
                } label: {
                    Text("Save").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Button("Cancel", role: .cancel) { model.cancelComposing() }
            } footer: {
                if let notice = model.notice {
                    Text(notice).foregroundStyle(Theme.danger)
                } else if let next = model.nextReminder {
                    Text("Next reminder \(Self.stamp(next)).")
                }
            }
        } else {
            Section {
                Button {
                    model.beginLogging()
                } label: {
                    Label(model.logButtonTitle, systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("cadenceSheet.log")
            } footer: {
                if let notice = model.notice {
                    Text(notice).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    // MARK: - History

    private func entryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Date AND time, spelled out. The grid only ever showed "2 days ago", which is no
            // help at all when you are trying to work out whether a dose was double-logged.
            Text(Self.stamp(entry.performedAt)).foregroundStyle(Theme.ink)
            if let note = entry.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // A visible menu as well as the swipe: swipe-to-delete was the only route to removing a
        // mis-logged entry, and an invisible gesture is what made the old tile hard to recover
        // from in the first place.
        .contextMenu {
            Button { model.beginEditing(entry) } label: {
                Label("Edit time", systemImage: "clock.arrow.circlepath")
            }
            Button(role: .destructive) { pendingDelete = entry } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = entry } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { model.beginEditing(entry) } label: {
                Label("Edit", systemImage: "clock")
            }
            .tint(Theme.primaryDeep)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit time") { model.beginEditing(entry) }
        .accessibilityAction(named: "Delete") { pendingDelete = entry }
    }

    @ViewBuilder
    private var fullRecord: some View {
        switch model.item.source {
        case .medication(let objectID):
            if let obj = try? services.medicationStore.context.existingObject(with: objectID),
               let med = obj as? Medication {
                MedicationDetailView(medication: med, services: services)
            }
        case .activityType(let objectID):
            if let obj = try? services.activityStore.context.existingObject(with: objectID),
               let type = obj as? ActivityType {
                CareActivityDetailView(type: type, services: services)
            }
        }
    }

    /// "Sep 2, 2026 at 9:03 AM" — one stamp format for every date this sheet shows.
    private static func stamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
