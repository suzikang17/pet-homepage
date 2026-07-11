// ios/PetHomepage/Notifications/RoutineReminderScheduler.swift
import Foundation

/// Schedules routine-task reminders through the shared NotificationScheduling. Pure enough to
/// unit-test with the FakeNotificationScheduler — never touches UNUserNotificationCenter.
///
/// Trigger shapes (chosen to respect iOS's 64-pending-notification budget):
/// - every-day task → ONE daily repeating trigger (dateComponents nil)
/// - partial-week task → one repeating weekly trigger per selected weekday
/// - one-off (today or future) → one-shot on its date; past one-offs get nothing
/// Closed template rows (effectiveUntil != nil, except a one-off's own window) get nothing.
///
/// Known v1 limitation: skipping a task for a single day does not suppress that day's
/// already-scheduled repeating notification.
final class RoutineReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar

    init(scheduler: NotificationScheduling, calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.calendar = calendar
    }

    func reminders(for task: RoutineTask, petName: String?) -> [PendingReminder] {
        let title = task.name
        let body: String
        if let petName, !petName.isEmpty {
            body = "Time for \(petName)'s \(task.name)"
        } else {
            body = "Time for \(task.name)"
        }

        func reminder(dateComponents: DateComponents?, repeats: Bool) -> PendingReminder {
            PendingReminder(kind: .routine, entityID: task.id, title: title, body: body,
                            hour: Int(task.hour), minute: Int(task.minute),
                            dateComponents: dateComponents, repeats: repeats)
        }

        if task.isOneOff {
            // One-shot on the one-off's day; nothing if that day is already over.
            let today = calendar.startOfDay(for: Date())
            guard task.effectiveFrom >= today else { return [] }
            let components = calendar.dateComponents([.year, .month, .day], from: task.effectiveFrom)
            return [reminder(dateComponents: components, repeats: false)]
        }

        guard task.effectiveUntil == nil else { return [] } // closed version: successor owns it

        if task.weekdayMask == Weekdays.all {
            return [reminder(dateComponents: nil, repeats: false)] // nil = daily repeating
        }
        return Weekdays.weekdays(in: task.weekdayMask).map { weekday in
            reminder(dateComponents: DateComponents(weekday: weekday), repeats: true)
        }
    }

    /// Cancel-then-schedule so narrowing a task's weekdays never leaves stale triggers behind.
    func syncTask(_ task: RoutineTask, petName: String?) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
        for reminder in reminders(for: task, petName: petName) {
            await scheduler.schedule(reminder)
        }
    }

    /// Cancels the task's triggers AND any pending snoozed re-fire — a snooze must not outlive
    /// its deleted task.
    func cancelTask(_ task: RoutineTask) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
        await scheduler.cancel(kind: .routineSnooze, entityID: task.id)
    }

    /// Full re-sync (app start / pet switch): clears the whole kind, then schedules the given
    /// tasks — pass the current template rows plus any not-yet-past one-offs.
    func syncAll(tasks: [RoutineTask], petName: String?) async {
        await scheduler.cancelAll(kind: .routine)
        for task in tasks {
            for reminder in reminders(for: task, petName: petName) {
                await scheduler.schedule(reminder)
            }
        }
    }
}
