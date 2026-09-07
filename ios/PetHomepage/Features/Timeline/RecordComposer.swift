// ios/PetHomepage/Features/Timeline/RecordComposer.swift
import SwiftUI

/// Creating a record, split out from the view that used to own it.
///
/// The Timeline's floating "+" carried both halves of adding something: the menu of record kinds,
/// and the editor sheet each one opens. When the stream moved into the Schedule tab those halves
/// had to separate — the menu now hangs off the Schedule header's "+" (which is shown on every
/// subtab, including the two that do not render the stream), while the sheets are presented by
/// the host view. Keeping both here means the list of things you can add exists once.
struct RecordAddMenuItems: View {
    let services: TimelineServices
    @Binding var addKind: TimelineKind?
    @Binding var showScan: Bool

    var body: some View {
        Button { addKind = .diary } label: { Label("Note", systemImage: "square.and.pencil") }
        Button { addKind = .activity } label: { Label("Activity", systemImage: "shower") }
        Button { addKind = .medication } label: { Label("Medication", systemImage: "pills") }
        Button { addKind = .symptom } label: {
            Label("Symptom", systemImage: "waveform.path.ecg")
        }
        // Low-frequency record types grouped under a submenu to keep the menu short.
        Menu {
            Button { addKind = .vaccine } label: { Label("Vaccine", systemImage: "syringe") }
            Button { addKind = .vet } label: { Label("Vet visit", systemImage: "stethoscope") }
            Button { addKind = .marker } label: {
                Label("Health marker", systemImage: "chart.xyaxis.line")
            }
        } label: {
            Label("Health record", systemImage: "cross.case")
        }
        if services.canScanRecords {
            Divider()
            Button { showScan = true } label: { Label("Scan a record", systemImage: "sparkles") }
        }
    }
}

/// The editor a picked record kind opens.
enum RecordEditors {
    @ViewBuilder
    static func addEditor(for kind: TimelineKind, services: TimelineServices) -> some View {
        switch kind {
        // A dose belongs to a medication, so it is logged from a Home tile, a notification, or
        // the medication's own screen — never created standalone from the add menu.
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
            MedicationEditView(store: services.medicationStore,
                               reminderScheduler: services.reminderScheduler,
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
            // Routine completions are created by checking off tasks on the Today subtab —
            // never from the add menu (which has no Routine entry).
            EmptyView()
        }
    }
}

extension View {
    /// Presents whichever editor `addKind` names, plus the record scanner.
    ///
    /// `services` is optional to match its hosts, which take it optionally for previews and
    /// tests; with nil there is nothing to present and the menu that sets these is absent too.
    func recordEditorSheets(services: TimelineServices?,
                            addKind: Binding<TimelineKind?>,
                            showScan: Binding<Bool>,
                            onDismiss: @escaping () -> Void) -> some View {
        self
            .sheet(item: addKind, onDismiss: onDismiss) { kind in
                if let services {
                    RecordEditors.addEditor(for: kind, services: services)
                }
            }
            .sheet(isPresented: showScan, onDismiss: onDismiss) {
                if let ex = services?.extractionService, let ing = services?.ingestionService {
                    RecordUploadView(extractionService: ex, ingestionService: ing)
                }
            }
    }
}
