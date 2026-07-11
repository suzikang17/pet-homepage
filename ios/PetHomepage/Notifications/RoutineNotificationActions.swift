// ios/PetHomepage/Notifications/RoutineNotificationActions.swift
import CoreData
import Foundation
import UserNotifications

/// The actionable category attached to routine reminders: long-pressing the notification on
/// the lock screen offers Mark as done / Skip today / Snooze 30 min.
enum RoutineNotificationAction {
    static let categoryID = "routineReminder"
    static let done = "routineMarkDone"
    static let skip = "routineSkipToday"
    static let snooze = "routineSnooze30"

    /// Registers the category with the system. Call once at launch, before any routine
    /// notification can be delivered.
    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let doneAction = UNNotificationAction(identifier: done, title: "Mark as done")
        let skipAction = UNNotificationAction(identifier: skip, title: "Skip today")
        let snoozeAction = UNNotificationAction(identifier: snooze, title: "Snooze 30 min")
        let category = UNNotificationCategory(identifier: categoryID,
                                              actions: [doneAction, skipAction, snoozeAction],
                                              intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
}

/// Applies a notification action to the routine data. Pure logic keyed by plain strings —
/// the UNUserNotificationCenterDelegate shim below extracts (actionIdentifier, request
/// identifier) and calls this, so tests never need a real UNNotificationResponse (which
/// can't be constructed).
final class RoutineActionHandler {
    private let context: NSManagedObjectContext
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date

    init(context: NSManagedObjectContext,
         scheduler: NotificationScheduling,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.context = context
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    /// Routes a notification action. The request identifier carries (kind, task id) — both the
    /// original routine reminder and a snoozed re-fire resolve to the same task.
    func handle(actionID: String, requestID: String) async {
        guard let (kind, taskID) = ReminderIdentifier.parse(requestID),
              kind == .routine || kind == .routineSnooze,
              let task = fetchTask(taskID) else { return }
        let store = RoutineStore(context: context, petStore: PetStore(context: context),
                                 calendar: calendar)
        switch actionID {
        case RoutineNotificationAction.done:
            // Dedupe: acting on a stale notification after the task was checked off in-app
            // must not create a second completion.
            if (try? store.completion(of: task, on: now())) == nil {
                _ = try? store.checkOff(task, on: now(), now: now())
            }
        case RoutineNotificationAction.skip:
            try? store.skip(task, on: now()) // idempotent
        case RoutineNotificationAction.snooze:
            await scheduleSnooze(for: task)
        default:
            break // plain tap (UNNotificationDefaultActionIdentifier) just opens the app
        }
    }

    private func fetchTask(_ id: UUID) -> RoutineTask? {
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// One-shot re-fire 30 minutes from now, under the dedicated snooze kind so it can never
    /// replace the task's repeating trigger. The snoozed notification carries the same
    /// actionable category, so it can itself be done/skipped/snoozed again.
    private func scheduleSnooze(for task: RoutineTask) async {
        let fireAt = now().addingTimeInterval(30 * 60)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: fireAt)
        let time = calendar.dateComponents([.hour, .minute], from: fireAt)
        let body: String
        if let petName = task.pet?.name, !petName.isEmpty {
            body = "Time for \(petName)'s \(task.name)"
        } else {
            body = "Time for \(task.name)"
        }
        let reminder = PendingReminder(kind: .routineSnooze,
                                       entityID: task.id,
                                       title: task.name,
                                       body: body,
                                       hour: time.hour ?? 9,
                                       minute: time.minute ?? 0,
                                       dateComponents: dateComponents,
                                       repeats: false)
        await scheduler.schedule(reminder)
    }
}

/// Thin UNUserNotificationCenterDelegate: extracts plain identifiers from the response and
/// delegates to RoutineActionHandler. Also lets reminders present as banners while the app
/// is foregrounded (the default is to silently swallow them).
final class RoutineNotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let handler: RoutineActionHandler

    init(handler: RoutineActionHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await handler.handle(actionID: response.actionIdentifier,
                             requestID: response.notification.request.identifier)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
