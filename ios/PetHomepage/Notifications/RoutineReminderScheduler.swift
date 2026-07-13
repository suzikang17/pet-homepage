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

    init(scheduler: NotificationScheduling, calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.calendar = calendar
    }

    /// Full re-sync: clears the whole routine kind, then schedules the given occurrences.
    /// Pending snoozed re-fires (their own kind) are left alone.
    func syncAll(occurrences: [RoutineReminderOccurrence], petName: String?) async {
        await scheduler.cancelAll(kind: .routine)
        for occurrence in occurrences {
            let body: String
            if let petName, !petName.isEmpty {
                body = "Time for \(petName)'s \(occurrence.task.name)"
            } else {
                body = "Time for \(occurrence.task.name)"
            }
            let components = calendar.dateComponents([.year, .month, .day], from: occurrence.day)
            await scheduler.schedule(PendingReminder(
                kind: .routine,
                entityID: occurrence.task.id,
                title: occurrence.task.name,
                body: body,
                hour: occurrence.hour,
                minute: occurrence.minute,
                dateComponents: components,
                repeats: false))
        }
    }

    /// Cancels the task's pending occurrences AND any pending snoozed re-fire — a snooze must
    /// not outlive its deleted task.
    func cancelTask(_ task: RoutineTask) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
        await scheduler.cancel(kind: .routineSnooze, entityID: task.id)
    }
}
