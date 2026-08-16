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

    private let medicationStore: MedicationStore
    private let activityStore: ActivityStore
    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let dueScheduler: DueReminderScheduler
    private let calendar: Calendar
    private let now: () -> Date

    init(medicationStore: MedicationStore,
         activityStore: ActivityStore,
         logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         dueScheduler: DueReminderScheduler,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.medicationStore = medicationStore
        self.activityStore = activityStore
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.dueScheduler = dueScheduler
        self.calendar = calendar
        self.now = now
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
                    // `startedAt` is this model's "next reminder date", not when the course began.
                    nextDue: med.startedAt)
            }

        // Only types with a real cadence. defaultIntervalDays == 0 means a one-off log type,
        // which by construction never gets a nextDueAt.
        let activities = ((try? activityStore.types(includeArchived: false)) ?? [])
            .filter { $0.defaultIntervalDays > 0 }
            .map { type in
                let latest = try? logStore.latestLog(of: type)
                return CadenceItem(
                    id: type.id,
                    source: .activityType(type.objectID),
                    name: type.name,
                    iconName: type.iconName,
                    subtitle: nil,
                    lastDone: latest?.performedAt,
                    nextDue: latest?.nextDueAt)
            }

        items = (medications + activities).sorted(by: Self.ordering(now: now(), calendar: calendar))
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
            await logger.log(med, at: when)
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
        }
        load()
    }
}
