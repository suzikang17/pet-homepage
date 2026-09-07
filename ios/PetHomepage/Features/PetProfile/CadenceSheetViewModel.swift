// ios/PetHomepage/Features/PetProfile/CadenceSheetViewModel.swift
import CoreData
import Foundation
import Observation

/// Drives the bottom sheet a cadence tile opens: one recurring thing's history, a confirmed
/// (and backdatable) way to log it, and per-entry correction and deletion.
///
/// This is a THIN WRAPPER, deliberately. Every mutation it exposes is delegated to code that
/// already exists — `CadenceCatalogueViewModel.log` for writes, and the two detail view models
/// for deletes and date corrections. Each of those owns a cadence-repair rule that this codebase
/// has already had duplicated into divergence once (see the header of `MedicationDoseLogger`),
/// and a third copy living here would be the same mistake with a new name.
@MainActor
@Observable
final class CadenceSheetViewModel {
    let item: CadenceItem

    /// Whichever record the tile stands for. Exactly one is non-nil.
    private let medication: MedicationDetailViewModel?
    private let activity: CareActivityDetailViewModel?

    private let catalogue: CadenceCatalogueViewModel
    private let calendar: Calendar
    private let now: () -> Date

    /// Newest first. Both backing view models already sort descending by `performedAt`.
    private(set) var entries: [LogEntry] = []

    /// Shown under the Log button when an attempt did not write. Currently only the same-day
    /// dedupe puts anything here.
    private(set) var notice: String?

    /// The inline log form's state. It lives here rather than in the view so that
    /// "already logged today → edit that entry instead" can retarget it.
    var isComposing = false
    var draftDate: Date
    var draftNote: String = ""

    /// Non-nil while the form is correcting an existing entry rather than adding a new one.
    private(set) var editingEntry: LogEntry?

    /// Fails when the tile's object id no longer resolves — the record was deleted underneath it.
    init?(item: CadenceItem,
          catalogue: CadenceCatalogueViewModel,
          services: TimelineServices,
          calendar: Calendar = .current,
          now: @escaping () -> Date = Date.init) {
        self.item = item
        self.catalogue = catalogue
        self.calendar = calendar
        self.now = now
        self.draftDate = now()

        switch item.source {
        case .medication(let objectID):
            guard let obj = try? services.medicationStore.context.existingObject(with: objectID),
                  let med = obj as? Medication else { return nil }
            self.medication = MedicationDetailViewModel(
                medication: med,
                logStore: services.logStore,
                reminderScheduler: services.reminderScheduler,
                calendar: calendar)
            self.activity = nil
        case .activityType(let objectID):
            guard let obj = try? services.activityStore.context.existingObject(with: objectID),
                  let type = obj as? ActivityType else { return nil }
            self.activity = CareActivityDetailViewModel(
                type: type,
                logStore: services.logStore,
                dueScheduler: services.dueScheduler)
            self.medication = nil
        }
        load()
    }

    // MARK: - Presentation

    var title: String { item.name }
    var iconName: String { item.iconName }
    var subtitle: String? {
        if let subtitle = item.subtitle, !subtitle.isEmpty { return subtitle }
        guard let activity, activity.hasCadence else { return nil }
        let days = activity.intervalDays
        return days == 1 ? "Every day" : "Every \(days) days"
    }

    var dueState: DueState { item.dueState(now: now(), calendar: calendar) }

    /// "Log a dose" reads wrong for a bath. Medications keep the clinical word; activities are
    /// named after themselves, matching `CareActivityDetailView`'s own button.
    var logButtonTitle: String {
        medication != nil ? "Log a dose" : "Log a \(item.name.lowercased())"
    }

    var historyTitle: String {
        medication != nil ? "Doses (\(entries.count))" : "History (\(entries.count))"
    }

    var isEmpty: Bool { entries.isEmpty }

    /// The next reminder this record is currently pointing at, for the form's live preview.
    var nextReminder: Date? {
        if let medication { return medication.medication.nextReminder }
        return activity?.nextDue
    }

    func load() {
        entries = medication?.doses ?? activity?.logs ?? []
    }

    // MARK: - Composing

    /// Opens the form for a NEW entry, defaulted to now.
    func beginLogging() {
        editingEntry = nil
        draftDate = now()
        draftNote = ""
        notice = nil
        isComposing = true
    }

    /// Opens the same form pointed at an existing entry, to correct when it happened.
    func beginEditing(_ entry: LogEntry) {
        editingEntry = entry
        draftDate = entry.performedAt
        draftNote = entry.note ?? ""
        notice = nil
        isComposing = true
    }

    func cancelComposing() {
        isComposing = false
        editingEntry = nil
        notice = nil
    }

    /// Writes the form — either a new entry or a correction to the one being edited.
    ///
    /// A deduped write is REPORTED rather than swallowed. `MedicationDoseLogger` offers
    /// `dedupe: false` for explicitly confirmed doses on exactly this reasoning — that silently
    /// discarding what someone typed is worse than a duplicate — but the honest third option is
    /// to write nothing and say so, then hand them the entry that already exists. That keeps the
    /// dedupe's protection and still never leaves a confirmed action unexplained.
    func commit() async {
        if let editingEntry {
            await applyEdit(to: editingEntry)
            isComposing = false
            self.editingEntry = nil
            return
        }

        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        switch await catalogue.log(item, at: draftDate, note: note.isEmpty ? nil : note) {
        case .logged:
            isComposing = false
            draftNote = ""
            notice = nil
        case .deduped:
            notice = "Already logged today — edit that entry instead."
            // Retarget the open form at the entry that blocked the write, so the fix is one tap
            // away rather than a hunt through the list.
            reload()
            if let clash = entries.first(where: { calendar.isDate($0.performedAt, inSameDayAs: draftDate) }) {
                beginEditing(clash)
                notice = "Already logged today — editing that entry."
            }
            return
        case .failed:
            notice = "Couldn't save that. Try again."
            return
        }
        reload()
    }

    private func applyEdit(to entry: LogEntry) async {
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned: String? = note.isEmpty ? nil : note
        if let medication {
            await medication.updateDose(entry, performedAt: draftDate, note: cleaned)
        } else if let activity {
            await activity.updateTime(of: entry, to: draftDate, note: cleaned)
        }
        reload()
    }

    // MARK: - Deleting

    func delete(_ entry: LogEntry) async {
        if let medication {
            await medication.deleteDose(entry)
        } else if let activity {
            await activity.delete(entry)
        }
        reload()
    }

    /// Refreshes this sheet AND the grid behind it — a delete or a backdated log changes the
    /// tile's badge and its position in the ordering, and leaving that stale is how the tile
    /// stops being trustworthy.
    private func reload() {
        medication?.load()
        activity?.load()
        load()
        catalogue.load()
    }
}
