// ios/PetHomepage/Features/Activities/CareActivityDetailView.swift
import SwiftUI

/// One care activity's own page: its cadence + every time it has been logged, with logging and
/// configuration both reachable from here. The ActivityType twin of MedicationDetailView.
///
/// This is where a Home tile leads: the tile is a shortcut for logging, and this screen is the
/// full record behind it — so "what did I do and when" and "how often should this happen" live
/// one tap from the thing itself rather than behind a gear in another tab.
struct CareActivityDetailView: View {
    @State private var model: CareActivityDetailViewModel
    @State private var showEdit = false
    @State private var showLog = false
    private let services: TimelineServices

    init(type: ActivityType, services: TimelineServices) {
        _model = State(initialValue: CareActivityDetailViewModel(
            type: type,
            logStore: services.logStore,
            dueScheduler: services.dueScheduler
        ))
        self.services = services
    }

    private var type: ActivityType { model.type }

    var body: some View {
        Form {
            Section("Cadence") {
                if model.hasCadence {
                    LabeledContent("Repeats", value: "Every \(model.intervalDays) days")
                    LabeledContent("Remind at") {
                        Text(String(format: "%02d:%02d", type.reminderHour, type.reminderMinute))
                    }
                } else {
                    LabeledContent("Repeats", value: "No repeat")
                }
                if let lastDone = model.lastDone {
                    LabeledContent("Last done") {
                        Text(lastDone, format: .dateTime.month().day().year())
                    }
                }
                if let nextDue = model.nextDue {
                    LabeledContent("Next due") {
                        Text(nextDue, format: .dateTime.month().day().year())
                    }
                }
            }

            Section("History (\(model.logs.count))") {
                Button {
                    showLog = true
                } label: {
                    Label("Log a \(type.name.lowercased())", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                if model.logs.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(model.logs, id: \.id) { log in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.performedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Theme.ink)
                            if let note = log.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.delete(log) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(type.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .onAppear { model.load() }
        .sheet(isPresented: $showEdit, onDismiss: { model.load() }) {
            ActivityTypeEditView(type: type) { name, category, iconName, intervalDays,
                                                reminderHour, reminderMinute in
                try? services.activityStore.updateType(
                    type, name: name, category: category, iconName: iconName,
                    defaultIntervalDays: intervalDays,
                    reminderHour: reminderHour, reminderMinute: reminderMinute)
            }
        }
        .sheet(isPresented: $showLog, onDismiss: { model.load() }) {
            ActivityLogEditView(logStore: services.logStore,
                                store: services.activityStore,
                                dueScheduler: services.dueScheduler,
                                editing: nil)
        }
    }
}
