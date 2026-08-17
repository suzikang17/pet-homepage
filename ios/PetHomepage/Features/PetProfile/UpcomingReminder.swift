// ios/PetHomepage/Features/PetProfile/UpcomingReminder.swift
import SwiftUI

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

/// One row of the upcoming list. Shared by Home's card and the Schedule tab's Upcoming subtab so
/// the two can never drift into showing the same reminder differently.
struct UpcomingReminderRow: View {
    let reminder: UpcomingReminder
    var now: Date = Date()

    var body: some View {
        let state = reminder.dueState(now: now)
        HStack(spacing: 10) {
            Image(systemName: reminder.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.badgeTint)
                .frame(width: 18)
            Text(reminder.name)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(state.badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.badgeTint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reminder.name), \(state.badgeText)")
    }
}
