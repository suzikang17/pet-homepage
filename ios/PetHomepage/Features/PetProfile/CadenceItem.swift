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
/// Hashable so it can drive `navigationDestination(item:)` — every stored property already is,
/// including `NSManagedObjectID`.
struct CadenceItem: Identifiable, Equatable, Hashable {
    /// The originating entity, held as an object ID rather than the object so this value type
    /// stays inert; the view model re-fetches on the main context when acting.
    enum Source: Equatable, Hashable {
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
    /// Today's photo for this item, already downsized. Nil when the pool is empty, and the
    /// tile falls back to its symbol.
    let dailyPhotoURL: URL?

    func dueState(now: Date, calendar: Calendar = .current) -> DueState {
        DueState.from(due: nextDue, now: now, calendar: calendar)
    }
}

extension DueState {
    /// The single day-granularity due computation, shared by cadence tiles and the upcoming list.
    /// Kept in one place deliberately: this codebase has repeatedly been bitten by the same rule
    /// existing in several copies that drifted apart.
    static func from(due: Date?, now: Date, calendar: Calendar = .current) -> DueState {
        guard let due else { return .noCadence }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days == 0 { return .dueToday }
        return days < 0 ? .overdue(days: -days) : .dueIn(days: days)
    }

    /// Sort rank: overdue first, then due today, then future, then undated.
    var sortRank: Int {
        switch self {
        case .overdue: 0
        case .dueToday: 1
        case .dueIn: 2
        case .noCadence: 3
        }
    }
}
