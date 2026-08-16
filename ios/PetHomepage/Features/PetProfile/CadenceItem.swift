// ios/PetHomepage/Features/PetProfile/CadenceItem.swift
import CoreData
import Foundation

/// How overdue (or not) a cadence item is, at DAY granularity. Day granularity is deliberate:
/// a dose due at 09:00 must not flip to "overdue" at 09:01 — it is due *today* until the day
/// turns over.
enum DueState: Equatable {
    case overdue(days: Int)
    case dueToday
    case dueIn(days: Int)
    /// No next-due date at all — a medication never logged, or an activity type never logged.
    case noCadence
}

/// One recurring thing on Home, projected from either a Medication or an ActivityType so the
/// view never branches on origin.
struct CadenceItem: Identifiable, Equatable {
    /// The originating entity, held as an object ID rather than the object so this value type
    /// stays inert; the view model re-fetches on the main context when acting.
    enum Source: Equatable {
        case medication(NSManagedObjectID)
        case activityType(NSManagedObjectID)
    }

    let id: UUID
    let source: Source
    let name: String
    let iconName: String
    /// Dosage for medications; nil for activities.
    let subtitle: String?
    let lastDone: Date?
    let nextDue: Date?

    func dueState(now: Date, calendar: Calendar = .current) -> DueState {
        guard let nextDue else { return .noCadence }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextDue)
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        if days == 0 { return .dueToday }
        return days < 0 ? .overdue(days: -days) : .dueIn(days: days)
    }
}
