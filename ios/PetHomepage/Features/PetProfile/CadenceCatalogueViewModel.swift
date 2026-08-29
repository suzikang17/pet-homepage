// ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift
import CoreData
import Foundation
import Observation

/// Aggregates everything on a cadence — medications and recurring activity types — into one
/// ordered list of tiles, and logs them.
///
/// This is a CATALOGUE, not a due list: an item appears whether or not anything is due, and
/// whether or not it has ever been logged. That is deliberate. The card this replaced could only
/// show what the app believed was due, and that belief has been demonstrated to go stale — it
/// also silently dropped never-logged items and excluded overdue ones.
@Observable
final class CadenceCatalogueViewModel {
    private(set) var items: [CadenceItem] = []

    /// Everything with a due date, most urgent first — including the vaccinations, vet visits and
    /// refills that have no tile in the grid.
    private(set) var upcoming: [UpcomingReminder] = []

    private let medicationStore: MedicationStore
    private let activityStore: ActivityStore
    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let dueScheduler: DueReminderScheduler
    private let calendar: Calendar
    private let now: () -> Date
    private let photoPool: PhotoPool

    init(medicationStore: MedicationStore,
         activityStore: ActivityStore,
         logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         dueScheduler: DueReminderScheduler,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         photoPool: PhotoPool? = nil) {
        self.medicationStore = medicationStore
        self.activityStore = activityStore
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.dueScheduler = dueScheduler
        self.calendar = calendar
        self.now = now
        self.photoPool = photoPool ?? PhotoPool(context: activityStore.context)
    }

    /// Bumped by every `load()`. Views drive `resolveDailyPhotos()` from `.task(id: loadToken)`.
    private(set) var loadToken = UUID()

    /// Picks whose thumbnail was not already on disk when `load()` ran, keyed by the tile's id.
    /// Drained by `resolveDailyPhotos()`.
    private var pendingPhotoPicks: [UUID: Photo] = [:]

    /// Today's photo for an activity type, and its thumbnail URL as a CACHE HIT ONLY — a `stat`,
    /// never a blob fault and never an ImageIO downsample.
    ///
    /// The pick itself (the two `PhotoPool` fetches) stays synchronous because it decides *which*
    /// photo, and the answer must be stable for the tile. Only the expensive part — generating a
    /// 264px JPEG on a miss — is deferred to `resolveDailyPhotos()`. Salted with the type's own
    /// id so two activities pick independently on the same day.
    private func dailyPhotoPick(for type: ActivityType) -> (photo: Photo, url: URL?)? {
        let photos = (try? photoPool.photos(for: .activityType(type))) ?? []
        guard let photo = DailyShuffle.pick(photos, on: now(), salt: type.id,
                                            calendar: calendar) else { return nil }
        return (photo, ThumbnailCache.shared.cachedURL(for: photo, size: .strip))
    }

    /// Generates the tile photos `load()` could not answer from the cache, off the main thread,
    /// publishing each tile as it lands. A tile still waiting shows its SF Symbol — the same
    /// rendering an activity type with no photos gets — so nothing flickers into a hole.
    @MainActor
    func resolveDailyPhotos() async {
        // Snapshot: the loop mutates `pendingPhotoPicks` as each pick lands.
        for (itemID, photo) in pendingPhotoPicks.map({ ($0.key, $0.value) }) {
            if Task.isCancelled { return }
            guard let url = await ThumbnailCache.shared.resolveURL(for: photo, size: .strip)
            else { continue }
            // `load()` may have replaced `items` while this was suspended; match by id.
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            items[index].dailyPhotoURL = url
            pendingPhotoPicks[itemID] = nil
        }
    }

    func load() {
        let medications = ((try? medicationStore.medications()) ?? [])
            .filter { $0.endedAt == nil || ($0.endedAt.map { $0 > now() } ?? true) }
            .map { med in
                CadenceItem(
                    id: med.id,
                    source: .medication(med.objectID),
                    name: med.drugName,
                    // Medication has no category attribute, so the icon is fixed — matching the
                    // "Active meds" stat tile.
                    iconName: "pills.fill",
                    subtitle: med.dosage,
                    lastDone: try? logStore.lastDose(for: med),
                    nextDue: med.nextReminder,
                    dailyPhotoURL: nil)
            }

        // Only types with a real cadence. defaultIntervalDays == 0 means a one-off log type,
        // which by construction never gets a nextDueAt.
        var picks: [UUID: Photo] = [:]
        let activities = ((try? activityStore.types(includeArchived: false)) ?? [])
            .filter { $0.defaultIntervalDays > 0 }
            .map { type in
                let latest = try? logStore.latestLog(of: type)
                let pick = dailyPhotoPick(for: type)
                if let pick, pick.url == nil { picks[type.id] = pick.photo }
                return CadenceItem(
                    id: type.id,
                    source: .activityType(type.objectID),
                    name: type.name,
                    iconName: type.iconName,
                    subtitle: nil,
                    lastDone: latest?.performedAt,
                    nextDue: latest?.nextDueAt,
                    dailyPhotoURL: pick?.url)
            }
        pendingPhotoPicks = picks

        items = (medications + activities).sorted(by: Self.ordering(now: now(), calendar: calendar))
        loadUpcoming()
        loadToken = UUID()
    }

    /// Builds the dated list. The grid's own items supply doses and activities; the three sources
    /// below have due dates but no tile, and were previously invisible on Home entirely.
    private func loadUpcoming() {
        var out: [UpcomingReminder] = items.compactMap { item in
            guard let due = item.nextDue else { return nil }
            let source: UpcomingReminder.Source
            switch item.source {
            case .medication: source = .dose
            case .activityType: source = .activity
            }
            return UpcomingReminder(id: "\(source.rawValue):\(item.id.uuidString)", source: source,
                                    name: item.name, iconName: item.iconName, due: due)
        }

        for vaccine in (try? logStore.vaccines()) ?? [] {
            guard let due = vaccine.nextDueAt else { continue }
            out.append(UpcomingReminder(id: "vaccination:\(vaccine.id.uuidString)",
                                        source: .vaccination,
                                        name: vaccine.title ?? "Vaccination",
                                        iconName: "syringe", due: due))
        }

        for visit in (try? logStore.vetVisits()) ?? [] {
            guard let due = visit.nextDueAt else { continue }
            out.append(UpcomingReminder(id: "vet:\(visit.id.uuidString)", source: .vetVisit,
                                        name: visit.title ?? "Vet visit",
                                        iconName: "stethoscope", due: due))
        }

        for med in (try? medicationStore.medications()) ?? [] {
            guard let refill = med.refillDueAt,
                  med.endedAt == nil || (med.endedAt.map { $0 > now() } ?? true) else { continue }
            out.append(UpcomingReminder(id: "refill:\(med.id.uuidString)", source: .refill,
                                        name: "Refill \(med.drugName)",
                                        iconName: "pills.circle", due: refill))
        }

        // Overdue first (most overdue at the top), then due today, then soonest. Deliberately
        // NOT filtered to `due >= now` — the card this replaces did that and so hid every
        // overdue item, which is the one thing a reminder list must never do.
        let clock = now()
        out.sort { lhs, rhs in
            let (l, r) = (lhs.dueState(now: clock, calendar: calendar).sortRank,
                          rhs.dueState(now: clock, calendar: calendar).sortRank)
            if l != r { return l < r }
            if lhs.due != rhs.due { return lhs.due < rhs.due }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        upcoming = out
    }

    /// Overdue first (most overdue at the top), then due today, then soonest, then things with no
    /// cadence at all. Ties broken by name so the grid is stable between loads.
    private static func ordering(now: Date, calendar: Calendar)
        -> (CadenceItem, CadenceItem) -> Bool {
        { lhs, rhs in
            func rank(_ item: CadenceItem) -> Int {
                switch item.dueState(now: now, calendar: calendar) {
                case .overdue: return 0
                case .dueToday: return 1
                case .dueIn: return 2
                case .noCadence: return 3
                }
            }
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            switch (lhs.nextDue, rhs.nextDue) {
            case let (ld?, rd?) where ld != rd: return ld < rd
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// The log just written from a tile, so the confirmation strip can offer Undo. Cleared when
    /// the strip is dismissed or undone.
    ///
    /// `previousStartedAt` is captured rather than recomputed on undo: for a medication,
    /// `nextReminder` is the next-reminder date, and recomputing it from whatever dose is newest
    /// after deletion silently fails when the undone dose was the only one — leaving the reminder
    /// pushed out for a dose that no longer exists.
    struct LoggedRecord: Equatable {
        let item: CadenceItem
        let entry: LogEntry
        let previousStartedAt: Date?
    }

    private(set) var lastLogged: LoggedRecord?

    /// Reverses the most recent tile log: deletes the entry and repairs the cadence + reminder
    /// the log advanced. One stray tap on a two-column grid is easy; making it unrecoverable is
    /// what would make one-tap logging a bad trade.
    @MainActor
    func undoLastLog() async {
        guard let record = lastLogged else { return }
        let (item, entry) = (record.item, record.entry)
        lastLogged = nil
        switch item.source {
        case .medication(let objectID):
            guard let obj = try? medicationStore.context.existingObject(with: objectID),
                  let med = obj as? Medication else { return }
            try? logStore.delete(entry)
            // Restore the exact next-reminder date the log overwrote.
            if let previous = record.previousStartedAt {
                med.nextReminder = previous
            }
            try? medicationStore.context.save()
            await reminderScheduler.sync(med)
        case .activityType:
            let type = entry.activityType
            await dueScheduler.cancelActivity(entry)
            try? logStore.delete(entry)
            if let type, let newLatest = try? logStore.latestLog(of: type) {
                await dueScheduler.syncActivity(newLatest)
            }
        }
        load()
    }

    func dismissConfirmation() { lastLogged = nil }

    /// Records the item as done now (or at an explicit date), then reloads.
    @MainActor
    func log(_ item: CadenceItem, at date: Date? = nil) async {
        let when = date ?? now()
        switch item.source {
        case .medication(let objectID):
            guard let obj = try? medicationStore.context.existingObject(with: objectID),
                  let med = obj as? Medication else { return }
            let logger = MedicationDoseLogger(logStore: logStore,
                                              reminderScheduler: reminderScheduler,
                                              calendar: calendar, now: now)
            // nil means the same-day dedupe swallowed it — nothing was written, so there is
            // nothing to offer an Undo for.
            let previousStartedAt = med.nextReminder
            guard await logger.log(med, at: when) != nil,
                  let entry = try? logStore.doses(for: med).first else { break }
            lastLogged = LoggedRecord(item: item, entry: entry,
                                      previousStartedAt: previousStartedAt)
        case .activityType(let objectID):
            guard let obj = try? activityStore.context.existingObject(with: objectID),
                  let type = obj as? ActivityType else { return }
            // Capture the prior latest-of-type BEFORE logging, so we can cancel its reminder —
            // mirrors ActivityLogEditViewModel.save() and CaptureReviewViewModel exactly.
            // DueReminderScheduler keys activity reminders by the LOG ENTRY's id, not the type's,
            // so a new entry does NOT replace the old entry's pending reminder: without this
            // cancel, logging a bath mid-cycle leaves the previous cycle's reminder armed and the
            // user is told "Time for Sandy's Bath" days after they already did it.
            let priorLatest = try? logStore.latestLog(of: type)
            // Same-day dedupe, matching MedicationDoseLogger.
            if let last = priorLatest?.performedAt, calendar.isDate(last, inSameDayAs: when) {
                return
            }
            guard let entry = try? logStore.logActivity(type: type, performedAt: when, note: nil,
                                                        intervalDays: Int(type.defaultIntervalDays))
            else { return }
            if let prior = priorLatest, prior.id != entry.id {
                await dueScheduler.cancelActivity(prior)
            }
            await dueScheduler.syncActivity(entry)
            lastLogged = LoggedRecord(item: item, entry: entry, previousStartedAt: nil)
        }
        load()
    }
}
