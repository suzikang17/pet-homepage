// ios/PetHomepage/Walk/WalkTimeSuggestion.swift
import Foundation

/// A walk slot's scheduled essentials, decoupled from Core Data so the decision is pure.
struct WalkSlotInfo: Equatable {
    let id: UUID
    let name: String
    let hour: Int
    let minute: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }
}

/// "Your schedule says 8:00 but you actually walk at 7:05" — suggest re-timing the slot.
struct WalkSlotTimeSuggestion: Equatable, Identifiable {
    let slot: WalkSlotInfo
    let suggestedHour: Int
    let suggestedMinute: Int
    let sampleCount: Int

    var id: UUID { slot.id }
}

/// Pairs learned habit times with the schedule's walk slots and proposes updates when they
/// disagree. Pure — Settings fetches slots + learned times and renders the result.
enum WalkTimeSuggestion {
    /// One suggestion per learned time, against the nearest walk slot in the same half of
    /// the day, only when the drift exceeds `habitSuggestDriftMinutes`. A learned time with
    /// no same-half-day slot yields nothing — creating slots is the schedule screen's job.
    static func suggestions(learned: [LearnedWalkTime], slots: [WalkSlotInfo],
                            tuning: WalkDetectionTuning = .default) -> [WalkSlotTimeSuggestion] {
        learned.compactMap { habit in
            let sameHalfDay = slots.filter {
                ($0.minutesSinceMidnight < 12 * 60) == (habit.minutesSinceMidnight < 12 * 60)
            }
            guard let nearest = sameHalfDay.min(by: {
                abs($0.minutesSinceMidnight - habit.minutesSinceMidnight)
                    < abs($1.minutesSinceMidnight - habit.minutesSinceMidnight)
            }) else { return nil }
            let drift = abs(nearest.minutesSinceMidnight - habit.minutesSinceMidnight)
            guard drift > tuning.habitSuggestDriftMinutes else { return nil }
            return WalkSlotTimeSuggestion(slot: nearest, suggestedHour: habit.hour,
                                          suggestedMinute: habit.minute,
                                          sampleCount: habit.sampleCount)
        }
    }
}
