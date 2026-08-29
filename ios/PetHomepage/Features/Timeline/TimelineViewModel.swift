// ios/PetHomepage/Features/Timeline/TimelineViewModel.swift
import Foundation
import Observation

/// The five record types, unified: everything in the app is "a typed thing that happened on a
/// date, maybe with a next-one-due." This is the read-side projection over the existing stores
/// (the data model itself stays five entities for now — see the planned HealthEvent unification).
enum TimelineKind: String, CaseIterable, Identifiable {
    case vaccine, vet, medication, dose, marker, symptom, activity, diary, routine
    var id: String { rawValue }

    var label: String {
        switch self {
        case .vaccine: "Vaccines"
        case .vet: "Vet"
        case .medication: "Meds"
        case .dose: "Doses"
        case .marker: "Health"
        case .symptom: "Symptoms"
        case .activity: "Activities"
        case .diary: "Diary"
        case .routine: "Routine"
        }
    }

    var systemImage: String {
        switch self {
        case .vaccine: "syringe"
        case .vet: "stethoscope"
        case .medication: "pills"
        case .dose: "pills.fill"
        case .marker: "chart.xyaxis.line"
        case .symptom: "waveform.path.ecg"
        case .activity: "shower"
        case .diary: "book"
        case .routine: "checklist"
        }
    }
}

/// The underlying record a row points back to, so a tap can open its existing editor/detail.
enum TimelineReference {
    case vaccine(LogEntry)
    case vet(LogEntry)
    case medication(Medication)
    case dose(LogEntry)
    case marker(LogEntry)
    case symptom(LogEntry)
    case activity(LogEntry)
    case diary(LogEntry)
    case routine(LogEntry)
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
    /// This entry's own first photo — never a pool/shuffle pick. A row is a specific event, so
    /// a rotating photo would misrepresent it. Nil when the entry has no photos.
    ///
    /// `var`, because it is filled in twice: `load()` sets it from a cache HIT only (a `stat`),
    /// and `TimelineViewModel.resolveThumbnails()` fills in the misses afterwards, off the main
    /// thread, publishing each row as it lands.
    var thumbnailURL: URL?
}

/// Aggregates the five record stores into one date-sorted stream, plus the "due soon" slice the
/// Home tab surfaces. Read-only — editing is delegated back to each type's existing editor.
/// One day's worth of timeline items — the stream is sectioned by day so rows can show a
/// time instead of repeating the date on every line.
struct TimelineDayGroup: Identifiable {
    let day: Date
    var items: [TimelineItem]

    var id: Date { day }

    /// "Today" / "Yesterday" / "Mon, Jul 13" — relative for the two days people think in.
    func title(calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

@Observable
final class TimelineViewModel {
    var items: [TimelineItem] = []
    var filter: TimelineKind?
    var errorMessage: String?
    /// All photos across diary entries + records, for the Photos view mode grid.
    var photos: [Photo] = []
    /// Bumped by every `load()`. Views drive `resolveThumbnails()` from `.task(id: loadToken)`,
    /// so each reload gets a fresh, structurally-cancelled resolve pass rather than an
    /// unstructured `Task` fired from inside `load()`.
    private(set) var loadToken = UUID()

    private let medicationStore: MedicationStore
    private let logStore: LogStore

    init(medicationStore: MedicationStore,
         logStore: LogStore) {
        self.medicationStore = medicationStore
        self.logStore = logStore
    }

    func load() {
        do {
            var out: [TimelineItem] = []
            out += try logStore.vaccines().map(TimelineItem.init(vaccine:))
            out += try logStore.vetVisits().map(TimelineItem.init(vet:))
            out += try medicationStore.medications().map(TimelineItem.init(medication:))
            out += try logStore.doses().map(TimelineItem.init(dose:))
            out += try logStore.markers().map(TimelineItem.init(marker:))
            out += try logStore.episodes().map(TimelineItem.init(symptom:))
            out += try logStore.activityLogs().map(TimelineItem.init(activity:))
            out += try logStore.diaryEntries().map(TimelineItem.init(diary:))
            out += try logStore.routineEntries().map(TimelineItem.init(routine:))
            items = out.sorted { $0.date > $1.date }
            photos = (try? logStore.allPhotos()) ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
        loadToken = UUID()
    }

    /// Fills in the row thumbnails `load()` could not answer from the cache.
    ///
    /// `load()` resolves cache HITS only — one `stat` per row, no blob fault and no downsample —
    /// so it costs what it did before thumbnails existed. Generation happens here instead: the
    /// blob is faulted on the main context's own thread (Core Data requires it, and `Photo` is
    /// not `Sendable`), the ImageIO downsample runs on a background executor, and each row is
    /// published as it lands so the list fills in progressively.
    ///
    /// This used to happen synchronously inside `TimelineItem.init`, which meant one cold-cache
    /// `load()` — and `PetProfileView.refresh()` calls `load()` on every Home appear — ran an
    /// unbounded number of 200–500 KB reads and downsamples back to back on the main thread.
    @MainActor
    func resolveThumbnails() async {
        var pending: [(id: String, photo: Photo)] = []
        for item in items {
            guard item.thumbnailURL == nil, let photo = item.thumbnailPhoto else { continue }
            pending.append((id: item.id, photo: photo))
        }
        for target in pending {
            if Task.isCancelled { return }
            guard let url = await ThumbnailCache.shared.resolveURL(for: target.photo, size: .row)
            else { continue }
            // `load()` may have replaced `items` while this was suspended, so rows are matched
            // by id rather than by index — a stale offset would write onto the wrong row.
            guard let index = items.firstIndex(where: { $0.id == target.id }) else { continue }
            items[index].thumbnailURL = url
        }
    }

    /// The current filter applied (nil = everything).
    var filtered: [TimelineItem] {
        guard let filter else {
            // A medication row is a prescription RECORD, not an event: it has no date of its own,
            // so TimelineItem borrows `nextReminder` — a FUTURE date, which is in the
            // future. Left in the unfiltered feed those records sort above everything that
            // actually happened, so a history view opens on a list of things that haven't
            // occurred yet. Doses are first-class rows now, so the medication's real activity is
            // still represented. The records stay reachable under the "Meds" filter below.
            return items.filter { $0.kind != .medication }
        }
        return items.filter { $0.kind == filter }
    }

    /// The filtered stream cut into day sections, newest day first (items already newest-first).
    /// Rows then show only a time — the day lives in the section header.
    func dayGroups(calendar: Calendar = .current) -> [TimelineDayGroup] {
        var groups: [TimelineDayGroup] = []
        for item in filtered {
            let day = calendar.startOfDay(for: item.date)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(TimelineDayGroup(day: day, items: [item]))
            }
        }
        return groups
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
            // Capture pet identity before delete — the LogEntry is a fault after being
            // removed from the context, so its relationships aren't safe to read afterward.
            let petID = v.pet?.id
            let petName = v.pet?.name
            try? services.logStore.delete(v)
            if let petID {
                let last = (try? services.logStore.mostRecentVisitDate()) ?? nil
                await services.dueScheduler.syncVetCadence(
                    petID: petID,
                    petName: petName,
                    lastVisit: last,
                    cadence: VetCadence(months: services.cadenceMonths, hour: 9, minute: 0)
                )
            }
            // else: entry had no pet — skip rather than collide with a shared sentinel.
        case .medication(let m):
            await services.reminderScheduler.cancel(m)
            try? services.medicationStore.delete(m)
        case .dose(let d):
            // Deleting a dose must move the cadence back to follow whatever dose is now newest —
            // `nextReminder` is exactly that, so leaving it advanced points the reminder a
            // full interval past a dose that no longer exists. Same repair as
            // MedicationDetailViewModel.deleteDose.
            let med = d.medication
            try? services.logStore.delete(d)
            if let med {
                let logger = MedicationDoseLogger(logStore: services.logStore,
                                                  reminderScheduler: services.reminderScheduler)
                if let newest = try? services.logStore.doses(for: med).first {
                    med.nextReminder = logger.nextDue(for: med, after: newest.performedAt)
                    try? med.managedObjectContext?.save()
                }
                await services.reminderScheduler.sync(med)
            }
        case .marker(let mk):
            try? services.logStore.delete(mk)
        case .symptom(let ep):
            try? services.logStore.delete(ep)
        case .activity(let log):
            let type = log.activityType
            await services.dueScheduler.cancelActivity(log)
            try? services.logStore.delete(log)
            // Re-arm the now-newest log of this type, so deleting the latest occurrence
            // doesn't silently drop the type's pending reminder.
            if let type, let newLatest = try? services.logStore.latestLog(of: type) {
                await services.dueScheduler.syncActivity(newLatest)
            }
        case .diary(let entry):
            try? services.logStore.delete(entry)
        case .routine(let entry):
            try? services.logStore.delete(entry)
        }
        load()
    }
}

private func formatMarker(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

extension TimelineItem {
    /// The photo this row's thumbnail is generated from — the entry's OWN first photo, and only
    /// for the five kinds that show one.
    ///
    /// `.dose`, `.marker` and `.symptom` carry a `LogEntry` too but deliberately render no
    /// thumbnail, and `.medication` is a prescription record rather than an event, so all four
    /// are excluded here exactly as they are in the initialisers.
    var thumbnailPhoto: Photo? {
        switch reference {
        case .vaccine(let entry), .vet(let entry), .activity(let entry),
             .diary(let entry), .routine(let entry):
            return entry.photoArray.first
        case .dose, .marker, .symptom, .medication:
            return nil
        }
    }

    init(vaccine v: LogEntry) {
        let thumbnailURL = v.photoArray.first
            .flatMap { ThumbnailCache.shared.cachedURL(for: $0, size: .row) }
        self.init(
            id: "vaccine:\(v.id.uuidString)",
            kind: .vaccine,
            date: v.performedAt,
            title: v.title ?? "Vaccine",
            subtitle: v.administeredBy.map { "by \($0)" },
            nextDue: v.nextDueAt,
            reference: .vaccine(v),
            thumbnailURL: thumbnailURL
        )
    }

    init(vet v: LogEntry) {
        let thumbnailURL = v.photoArray.first
            .flatMap { ThumbnailCache.shared.cachedURL(for: $0, size: .row) }
        self.init(
            id: "vet:\(v.id.uuidString)",
            kind: .vet,
            date: v.performedAt,
            title: v.clinicName ?? "Vet visit",
            subtitle: v.title ?? v.vetName,
            nextDue: v.nextDueAt,
            reference: .vet(v),
            thumbnailURL: thumbnailURL
        )
    }

    /// A dose that was actually GIVEN — an event, dated when it happened. Distinct from the
    /// `.medication` row, which is the prescription record and carries no event date at all.
    init(dose d: LogEntry) {
        let drug = d.medication?.drugName ?? "Medication"
        self.init(
            id: "dose:\(d.id.uuidString)",
            kind: .dose,
            date: d.performedAt,
            title: "Gave \(drug)",
            subtitle: [d.medication?.dosage, d.note]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            nextDue: nil,
            reference: .dose(d),
            thumbnailURL: nil
        )
    }

    init(medication m: Medication) {
        self.init(
            id: "med:\(m.id.uuidString)",
            kind: .medication,
            date: m.nextReminder,
            title: m.drugName,
            subtitle: [m.dosage, m.frequency].filter { !$0.isEmpty }.joined(separator: " · "),
            nextDue: m.refillDueAt,
            reference: .medication(m),
            thumbnailURL: nil
        )
    }

    init(marker mk: LogEntry) {
        let unit = mk.unit.map { " \($0)" } ?? ""
        self.init(
            id: "marker:\(mk.id.uuidString)",
            kind: .marker,
            date: mk.performedAt,
            title: "\(mk.markerType.displayName): \(formatMarker(mk.value))\(unit)",
            subtitle: nil,
            nextDue: nil,
            reference: .marker(mk),
            thumbnailURL: nil
        )
    }

    init(symptom ep: LogEntry) {
        self.init(
            id: "symptom:\(ep.id.uuidString)",
            kind: .symptom,
            date: ep.performedAt,
            title: ep.title ?? ep.category.displayName,
            subtitle: ep.status == .active ? "Active" : "Resolved",
            nextDue: nil,
            reference: .symptom(ep),
            thumbnailURL: nil
        )
    }

    init(activity log: LogEntry) {
        let base = (log.note?.isEmpty == false) ? log.note : log.activityType?.category.displayName
        let duration = log.durationMinutes.map { "\($0) min" }
        let combined = [duration, base].compactMap { $0 }.joined(separator: " · ")
        let thumbnailURL = log.photoArray.first
            .flatMap { ThumbnailCache.shared.cachedURL(for: $0, size: .row) }
        self.init(
            id: "activity:\(log.id.uuidString)",
            kind: .activity,
            date: log.performedAt,
            title: log.activityType?.name ?? "Activity",
            subtitle: combined.isEmpty ? nil : combined,
            nextDue: log.nextDueAt,
            reference: .activity(log),
            thumbnailURL: thumbnailURL
        )
    }

    init(routine entry: LogEntry) {
        let photoCount = entry.photoArray.count
        let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (note?.isEmpty == false) ? note
            : (photoCount > 0 ? "\(photoCount) photo\(photoCount == 1 ? "" : "s")" : nil)
        let duration = entry.durationMinutes.map { "\($0) min" }
        let combined = [duration, base].compactMap { $0 }.joined(separator: " · ")
        let thumbnailURL = entry.photoArray.first
            .flatMap { ThumbnailCache.shared.cachedURL(for: $0, size: .row) }
        self.init(
            id: "routine:\(entry.id.uuidString)",
            kind: .routine,
            date: entry.performedAt,
            title: entry.title ?? "Routine",
            subtitle: combined.isEmpty ? nil : combined,
            nextDue: nil,
            reference: .routine(entry),
            thumbnailURL: thumbnailURL
        )
    }

    init(diary entry: LogEntry) {
        let trimmedNote = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstLine = trimmedNote
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init)
        let photoCount = entry.photoArray.count
        let thumbnailURL = entry.photoArray.first
            .flatMap { ThumbnailCache.shared.cachedURL(for: $0, size: .row) }
        self.init(
            id: "diary:\(entry.id.uuidString)",
            kind: .diary,
            date: entry.performedAt,
            title: (firstLine?.isEmpty == false) ? firstLine! : "Diary entry",
            subtitle: photoCount > 0 ? "\(photoCount) photo\(photoCount == 1 ? "" : "s")" : nil,
            nextDue: nil,
            reference: .diary(entry),
            thumbnailURL: thumbnailURL
        )
    }
}
