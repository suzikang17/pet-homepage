// ios/PetHomepage/Features/Timeline/TimelineViewModel.swift
import Foundation
import Observation

/// The five record types, unified: everything in the app is "a typed thing that happened on a
/// date, maybe with a next-one-due." This is the read-side projection over the existing stores
/// (the data model itself stays five entities for now — see the planned HealthEvent unification).
enum TimelineKind: String, CaseIterable, Identifiable {
    case vaccine, vet, medication, marker, symptom, activity
    var id: String { rawValue }

    var label: String {
        switch self {
        case .vaccine: "Vaccines"
        case .vet: "Vet"
        case .medication: "Meds"
        case .marker: "Health"
        case .symptom: "Symptoms"
        case .activity: "Activities"
        }
    }

    var systemImage: String {
        switch self {
        case .vaccine: "syringe"
        case .vet: "stethoscope"
        case .medication: "pills"
        case .marker: "chart.xyaxis.line"
        case .symptom: "waveform.path.ecg"
        case .activity: "shower"
        }
    }
}

/// The underlying record a row points back to, so a tap can open its existing editor/detail.
enum TimelineReference {
    case vaccine(LogEntry)
    case vet(VetVisit)
    case medication(Medication)
    case marker(HealthMarker)
    case symptom(SymptomEpisode)
    case activity(LogEntry)
}

/// One row in the unified timeline.
struct TimelineItem: Identifiable {
    let id: String
    let kind: TimelineKind
    let date: Date
    let title: String
    let subtitle: String?
    let nextDue: Date?
    let reference: TimelineReference
}

/// Aggregates the five record stores into one date-sorted stream, plus the "due soon" slice the
/// Home tab surfaces. Read-only — editing is delegated back to each type's existing editor.
@Observable
final class TimelineViewModel {
    var items: [TimelineItem] = []
    var filter: TimelineKind?
    var errorMessage: String?

    private let vetVisitStore: VetVisitStore
    private let medicationStore: MedicationStore
    private let healthMarkerStore: HealthMarkerStore
    private let symptomEpisodeStore: SymptomEpisodeStore
    private let logStore: LogStore

    init(vetVisitStore: VetVisitStore,
         medicationStore: MedicationStore,
         healthMarkerStore: HealthMarkerStore,
         symptomEpisodeStore: SymptomEpisodeStore,
         logStore: LogStore) {
        self.vetVisitStore = vetVisitStore
        self.medicationStore = medicationStore
        self.healthMarkerStore = healthMarkerStore
        self.symptomEpisodeStore = symptomEpisodeStore
        self.logStore = logStore
    }

    func load() {
        do {
            var out: [TimelineItem] = []
            out += try logStore.vaccines().map(TimelineItem.init(vaccine:))
            out += try vetVisitStore.visits().map(TimelineItem.init(vet:))
            out += try medicationStore.medications().map(TimelineItem.init(medication:))
            out += try healthMarkerStore.markers().map(TimelineItem.init(marker:))
            out += try symptomEpisodeStore.episodes().map(TimelineItem.init(symptom:))
            out += try logStore.activityLogs().map(TimelineItem.init(activity:))
            items = out.sorted { $0.date > $1.date }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// The current filter applied (nil = everything).
    var filtered: [TimelineItem] {
        guard let filter else { return items }
        return items.filter { $0.kind == filter }
    }

    /// Records whose next-due falls within `days` from `now`, soonest first. Powers Home's "Due soon".
    func dueSoon(within days: Int = 30, now: Date = Date()) -> [TimelineItem] {
        guard let horizon = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        return items
            .filter { item in
                guard let due = item.nextDue else { return false }
                return due >= now && due <= horizon
            }
            .sorted { ($0.nextDue ?? .distantFuture) < ($1.nextDue ?? .distantFuture) }
    }

    /// Delete a record, cancelling any reminder it owned, then reload the stream.
    func delete(_ item: TimelineItem, using services: TimelineServices) async {
        switch item.reference {
        case .vaccine(let v):
            await services.dueScheduler.cancelVaccination(v)
            try? services.logStore.delete(v)
        case .vet(let v):
            try? services.vetVisitStore.delete(v)
            let last = (try? services.vetVisitStore.mostRecentVisitDate()) ?? nil
            await services.dueScheduler.syncVetCadence(
                lastVisit: last,
                cadence: VetCadence(months: services.cadenceMonths, hour: 9, minute: 0)
            )
        case .medication(let m):
            await services.reminderScheduler.cancel(m)
            try? services.medicationStore.delete(m)
        case .marker(let mk):
            try? services.healthMarkerStore.delete(mk)
        case .symptom(let ep):
            try? services.symptomEpisodeStore.delete(ep)
        case .activity(let log):
            let type = log.activityType
            await services.dueScheduler.cancelActivity(log)
            try? services.logStore.delete(log)
            // Re-arm the now-newest log of this type, so deleting the latest occurrence
            // doesn't silently drop the type's pending reminder.
            if let type, let newLatest = try? services.logStore.latestLog(of: type) {
                await services.dueScheduler.syncActivity(newLatest)
            }
        }
        load()
    }
}

private func formatMarker(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

extension TimelineItem {
    init(vaccine v: LogEntry) {
        self.init(
            id: "vaccine:\(v.id.uuidString)",
            kind: .vaccine,
            date: v.performedAt,
            title: v.title ?? "Vaccine",
            subtitle: v.administeredBy.map { "by \($0)" },
            nextDue: v.nextDueAt,
            reference: .vaccine(v)
        )
    }

    init(vet v: VetVisit) {
        self.init(
            id: "vet:\(v.id.uuidString)",
            kind: .vet,
            date: v.occurredAt,
            title: v.clinicName ?? "Vet visit",
            subtitle: v.reason ?? v.vetName,
            nextDue: v.nextVisitDate,
            reference: .vet(v)
        )
    }

    init(medication m: Medication) {
        self.init(
            id: "med:\(m.id.uuidString)",
            kind: .medication,
            date: m.startedAt,
            title: m.drugName,
            subtitle: [m.dosage, m.frequency].filter { !$0.isEmpty }.joined(separator: " · "),
            nextDue: m.refillDueAt,
            reference: .medication(m)
        )
    }

    init(marker mk: HealthMarker) {
        let unit = mk.unit.map { " \($0)" } ?? ""
        self.init(
            id: "marker:\(mk.id.uuidString)",
            kind: .marker,
            date: mk.recordedAt,
            title: "\(mk.markerType.displayName): \(formatMarker(mk.value))\(unit)",
            subtitle: nil,
            nextDue: nil,
            reference: .marker(mk)
        )
    }

    init(symptom ep: SymptomEpisode) {
        self.init(
            id: "symptom:\(ep.id.uuidString)",
            kind: .symptom,
            date: ep.startedAt,
            title: ep.title ?? ep.category.displayName,
            subtitle: ep.statusRaw == EpisodeStatus.active.rawValue ? "Active" : "Resolved",
            nextDue: nil,
            reference: .symptom(ep)
        )
    }

    init(activity log: LogEntry) {
        self.init(
            id: "activity:\(log.id.uuidString)",
            kind: .activity,
            date: log.performedAt,
            title: log.activityType?.name ?? "Activity",
            subtitle: (log.note?.isEmpty == false) ? log.note : log.activityType?.category.displayName,
            nextDue: log.nextDueAt,
            reference: .activity(log)
        )
    }
}
