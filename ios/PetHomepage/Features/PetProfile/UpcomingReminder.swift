// ios/PetHomepage/Features/PetProfile/UpcomingReminder.swift
import Foundation

/// One dated thing on Home's "Upcoming reminders" list.
///
/// This deliberately spans MORE than the Care routine grid. The grid covers what you *do* on a
/// cadence — doses and activities — and each of those tiles carries its own badge. But
/// vaccinations, vet visits and refills also have due dates and have no tile at all, so before
/// this list existed the only place they surfaced was a notification you might have missed. Those
/// are exactly the "nothing lapses" cases, so the list answers "what's coming" completely and
/// accepts that doses and activities appear both here and as a tile.
struct UpcomingReminder: Identifiable, Equatable {
    enum Source: String {
        case dose, activity, vaccination, vetVisit, refill
    }

    let id: String
    let source: Source
    let name: String
    let iconName: String
    let due: Date

    func dueState(now: Date, calendar: Calendar = .current) -> DueState {
        DueState.from(due: due, now: now, calendar: calendar)
    }
}
