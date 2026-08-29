// ios/PetHomepage/Features/Activities/CareActivityDetailViewModel.swift
import Foundation
import Observation

/// Drives one care activity's own page: its cadence plus every time it has been logged.
/// The ActivityType twin of MedicationDetailViewModel.
@Observable
final class CareActivityDetailViewModel {
    let type: ActivityType
    private(set) var logs: [LogEntry] = []
    /// Today's photo for this activity, at hero resolution. Nil when the pool is empty, and the
    /// screen renders with no hero block at all.
    private(set) var heroPhotoURL: URL?

    private let logStore: LogStore
    private let dueScheduler: DueReminderScheduler
    private let photoPool: PhotoPool
    private let now: () -> Date

    /// `photoPool` defaults from `logStore.context` — this view model has no `ActivityStore` of
    /// its own, but `type` and `logStore` already share the same context, mirroring
    /// `CadenceCatalogueViewModel`'s `PhotoPool(context: activityStore.context)` wiring.
    init(type: ActivityType, logStore: LogStore, dueScheduler: DueReminderScheduler,
         photoPool: PhotoPool? = nil, now: @escaping () -> Date = Date.init) {
        self.type = type
        self.logStore = logStore
        self.dueScheduler = dueScheduler
        self.photoPool = photoPool ?? PhotoPool(context: logStore.context)
        self.now = now
        load()
    }

    /// Newest first — `LogStore.logs(of:)` already sorts descending by performedAt. Reloads the
    /// hero photo alongside the history so both refresh together after every log/delete/edit.
    func load() {
        logs = (try? logStore.logs(of: type)) ?? []
        loadHeroPhoto()
    }

    /// Salted with the type's own id so two activities pick independently on the same day.
    private func loadHeroPhoto() {
        let photos = (try? photoPool.photos(for: .activityType(type))) ?? []
        heroPhotoURL = DailyShuffle.pick(photos, on: now(), salt: type.id)
            .flatMap { ThumbnailCache.shared.url(for: $0, size: .hero) }
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
