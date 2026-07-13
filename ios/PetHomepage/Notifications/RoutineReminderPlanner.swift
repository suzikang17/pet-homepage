// ios/PetHomepage/Notifications/RoutineReminderPlanner.swift
import CoreData
import Foundation

/// Decides which routine reminders should exist right now: the next `horizonDays` days'
/// slots, minus completed and skipped days, at each day's effective (override-aware) time,
/// dropping occurrences already in the past. One place decides; every resync point — app
/// launch, schedule mutations, notification actions — calls `resync`.
enum RoutineReminderPlanner {
    /// Days of one-shot reminders kept pending. Every resync point refreshes the window, so
    /// it only needs to outlast a realistic stretch of not opening the app; 5 keeps
    /// tasks × horizon comfortably under iOS's 64-pending-notification cap.
    static let horizonDays = 5

    static func occurrences(store: RoutineStore, calendar: Calendar = .current,
                            now: Date = Date()) throws -> [RoutineReminderOccurrence] {
        var result: [RoutineReminderOccurrence] = []
        let start = calendar.startOfDay(for: now)
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for slot in try store.slots(for: day) where !slot.isCompleted && !slot.isSkipped {
                guard let fireAt = calendar.date(bySettingHour: slot.hour, minute: slot.minute,
                                                 second: 0, of: day),
                      fireAt > now else { continue }
                result.append(RoutineReminderOccurrence(task: slot.task, day: day,
                                                        hour: slot.hour, minute: slot.minute))
            }
        }
        return result
    }

    /// Recomputes and reschedules everything. Cheap (a few day-slot reads), so callers just
    /// fire-and-forget after any mutation that could change what should fire.
    static func resync(context: NSManagedObjectContext,
                       using reminderScheduler: RoutineReminderScheduler,
                       calendar: Calendar = .current,
                       now: Date = Date()) async {
        let petStore = PetStore(context: context)
        let store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        let planned = (try? occurrences(store: store, calendar: calendar, now: now)) ?? []
        let petName = (try? petStore.currentPet())?.name
        await reminderScheduler.syncAll(occurrences: planned, petName: petName)
    }
}
