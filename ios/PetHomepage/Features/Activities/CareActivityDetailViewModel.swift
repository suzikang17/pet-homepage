// ios/PetHomepage/Features/Activities/CareActivityDetailViewModel.swift
import Foundation
import Observation

/// Drives one care activity's own page: its cadence plus every time it has been logged.
/// The ActivityType twin of MedicationDetailViewModel.
@Observable
final class CareActivityDetailViewModel {
    let type: ActivityType
    private(set) var logs: [LogEntry] = []

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler

    init(type: ActivityType, logStore: LogStore, dueScheduler: DueReminderScheduler) {
        self.type = type
        self.logStore = logStore
        self.dueScheduler = dueScheduler
        load()
    }

    /// Newest first — `LogStore.logs(of:)` already sorts descending by performedAt.
    func load() {
        logs = (try? logStore.logs(of: type)) ?? []
    }

    var lastDone: Date? { logs.first?.performedAt }
    var nextDue: Date? { logs.first?.nextDueAt }
    var intervalDays: Int { Int(type.defaultIntervalDays) }
    var hasCadence: Bool { type.defaultIntervalDays > 0 }

    /// Deletes one logged occurrence and repairs the reminder chain.
    ///
    /// Activity reminders are keyed by the LOG ENTRY's id, so deleting the newest entry would
    /// otherwise leave the type with no pending reminder at all — mirrors TimelineViewModel's
    /// activity delete path exactly.
    @MainActor
    func delete(_ log: LogEntry) async {
        await dueScheduler.cancelActivity(log)
        try? logStore.delete(log)
        load()
        if let newLatest = logs.first {
            await dueScheduler.syncActivity(newLatest)
        }
    }
}
