// ios/PetHomepage/Walk/WalkSlotFinder.swift
import CoreData
import Foundation

/// Finds the routine slot a detected walk should attach to: the nearest uncompleted,
/// unskipped slot scheduled within the attach window around `date`. Nil means the walk
/// logs as a plain activity instead.
enum WalkSlotFinder {
    static func openWalkSlot(near date: Date, withinMinutes: Int,
                             context: NSManagedObjectContext,
                             defaults: UserDefaults = .standard,
                             calendar: Calendar = .current) throws -> RoutineTask? {
        let petStore = PetStore(context: context, defaults: defaults)
        let store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
        let slots = try store.slots(for: date)
        let window = TimeInterval(withinMinutes * 60)

        var best: (task: RoutineTask, distance: TimeInterval)?
        for slot in slots where !slot.isCompleted && !slot.isSkipped && isWalkLike(slot.task) {
            guard let slotTime = calendar.date(bySettingHour: slot.hour, minute: slot.minute,
                                               second: 0, of: date) else { continue }
            let distance = abs(slotTime.timeIntervalSince(date))
            guard distance <= window else { continue }
            if best == nil || distance < best!.distance {
                best = (slot.task, distance)
            }
        }
        return best?.task
    }

    /// A walk should only ever complete a walk-shaped slot — never Breakfast just because
    /// it's the nearest open row.
    private static func isWalkLike(_ task: RoutineTask) -> Bool {
        task.category == .play || task.category == .training
            || task.name.localizedCaseInsensitiveContains("walk")
    }
}
