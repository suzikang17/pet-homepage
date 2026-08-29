// ios/PetHomepage/Notifications/RoutineReminderScheduler.swift
import Foundation

/// One concrete "remind for this task on this day at this time" — computed by
/// RoutineReminderPlanner from the day's real state (completions, skips, per-day time
/// overrides), so a reminder never fires for something already done, skipped, or moved.
struct RoutineReminderOccurrence: Equatable {
    let task: RoutineTask
    /// Start of the occurrence's day.
    let day: Date
    let hour: Int
    let minute: Int
}

/// Schedules routine-task reminders through the shared NotificationScheduling. Pure enough to
/// unit-test with the FakeNotificationScheduler — never touches UNUserNotificationCenter.
///
/// Occurrence model (replaces the old template-derived repeating triggers): every sync clears
/// the routine kind and schedules ONE-SHOT reminders for the planner's horizon, each derived
/// from that day's actual state. Repeating triggers can't represent day state — they were why
/// completed/skipped tasks still fired and per-day time changes were ignored.
/// Budget: tasks × RoutineReminderPlanner.horizonDays stays well under iOS's 64-pending cap;
/// resyncs happen on launch, on schedule mutations, and after notification actions.
final class RoutineReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    /// Source of today's attachment photo for routine/walk-slot reminders — this is the first
    /// real caller of the `.routineTask` union built for `PhotoPool` (it also pulls in
    /// auto-detected walk logs for walk tasks). nil (the default, and every existing call site
    /// until the composition root is updated) means no attachment lookup at all, matching
    /// today's behavior exactly. RoutineReminderScheduler has no NSManagedObjectContext of its
    /// own — like DueReminderScheduler, callers that want photos pass a real PhotoPool in.
    private let photoPool: PhotoPool?

    init(scheduler: NotificationScheduling, calendar: Calendar = .current, photoPool: PhotoPool? = nil) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.photoPool = photoPool
    }

    /// Per-`syncAll` memo for the attachment lookup. See `syncAll` for why it exists.
    private struct AttachmentMemo {
        /// Pool photos by task LINEAGE id — the key `PhotoPool` itself queries on.
        var pools: [UUID: [Photo]] = [:]
        /// Resolved thumbnail (or a cached nil) by photo id.
        var thumbnails: [UUID: URL?] = [:]
    }

    /// Today's attachment photo for a routine/walk-slot occurrence, or nil if there is no pool,
    /// no photos, or no thumbnail could be produced.
    ///
    /// Salted with the task's LINEAGE id, not its per-version `id`. `PhotoPool` queries
    /// `routineLineageID`, so the pool is lineage-scoped; a version-scoped salt meant that
    /// editing a template at midday spawned a successor with a fresh `id` and re-derived a
    /// different pick against an identical pool — the reminder photo changing for the rest of
    /// the same day, which is exactly the "changes under your finger" behaviour the design
    /// rejected. The salt and the pool are now keyed on the same identity.
    private func attachmentURL(for task: RoutineTask, on day: Date,
                               memo: inout AttachmentMemo) -> URL? {
        guard let photoPool else { return nil }
        let lineage = task.lineageID
        let photos: [Photo]
        if let cached = memo.pools[lineage] {
            photos = cached
        } else {
            photos = (try? photoPool.photos(for: .routineTask(task))) ?? []
            memo.pools[lineage] = photos
        }
        guard let photo = DailyShuffle.pick(photos, on: day, salt: lineage, calendar: calendar),
              let photoID = ThumbnailCache.identifier(of: photo) else { return nil }
        if let cached = memo.thumbnails[photoID] { return cached }
        let url = ThumbnailCache.shared.url(forPhotoID: photoID, size: .notification,
                                            imageData: photo.imageData)
        memo.thumbnails[photoID] = url
        return url
    }

    /// Full re-sync: clears the whole routine kind, then schedules the given occurrences.
    /// Pending snoozed re-fires (their own kind) are left alone.
    func syncAll(occurrences: [RoutineReminderOccurrence], petName: String?) async {
        await scheduler.cancelAll(kind: .routine)
        // The attachment lookup is memoised across the whole resync rather than recomputed per
        // occurrence. The horizon is 5 days, so a handful of slots produces up to ~30
        // occurrences, and every one of them used to run its own pair of Core Data fetches plus
        // a possible 800px downsample and JPEG write. `resync` runs on launch, on every schedule
        // mutation, on every check-off, and from the notification-action handler, so that cost
        // sat directly behind the app's most-tapped control.
        //
        // Two keys, because there are two distinct units of work: the pool query is per task
        // lineage (5 days of one slot share one pool), and the thumbnail is per photo (a small
        // pool means the same photo is picked for several days).
        var memo = AttachmentMemo()
        for occurrence in occurrences {
            let body: String
            if let petName, !petName.isEmpty {
                body = "Time for \(petName)'s \(occurrence.task.name)"
            } else {
                body = "Time for \(occurrence.task.name)"
            }
            let components = calendar.dateComponents([.year, .month, .day], from: occurrence.day)
            let attachment = attachmentURL(for: occurrence.task, on: occurrence.day, memo: &memo)
            await scheduler.schedule(PendingReminder(
                kind: .routine,
                entityID: occurrence.task.id,
                title: occurrence.task.name,
                body: body,
                hour: occurrence.hour,
                minute: occurrence.minute,
                dateComponents: components,
                repeats: false,
                attachmentURL: attachment))
        }
    }

    /// Cancels the task's pending occurrences AND any pending snoozed re-fire — a snooze must
    /// not outlive its deleted task.
    func cancelTask(_ task: RoutineTask) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
        await scheduler.cancel(kind: .routineSnooze, entityID: task.id)
    }
}
