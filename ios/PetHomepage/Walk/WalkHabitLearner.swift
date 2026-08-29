// ios/PetHomepage/Walk/WalkHabitLearner.swift
import CoreData
import Foundation

/// A time of day the user habitually walks, learned from logged walk history.
struct LearnedWalkTime: Equatable {
    let hour: Int
    let minute: Int
    let sampleCount: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }
}

/// Learns the user's usual walk times from history — walks are logged with real start
/// times (backdated to the home exit), so a few weeks of use is enough to know "mornings
/// around 7:05". Detection then treats an exit near a learned time as probably-a-walk
/// (fast confirm), and Settings can suggest re-timing a drifted schedule slot.
///
/// The core is pure; `learnedTimes(context:...)` is the Core Data wrapper.
enum WalkHabitLearner {
    /// Clusters walk starts into morning (< noon) and afternoon/evening (≥ noon), takes each
    /// cluster's median start, keeps only samples within `habitSpreadMinutes` of it, and
    /// calls the cluster a habit when `habitMinSamples` remain. The median + trim makes one
    /// unusually early or late day irrelevant.
    static func learnedTimes(from starts: [Date], calendar: Calendar = .current,
                             tuning: WalkDetectionTuning = .default) -> [LearnedWalkTime] {
        let minutes = starts.map { minutesSinceMidnight(of: $0, calendar: calendar) }
        let clusters = [minutes.filter { $0 < 12 * 60 }, minutes.filter { $0 >= 12 * 60 }]
        return clusters.compactMap { habit(in: $0, tuning: tuning) }
    }

    /// True when `date` lands within `windowMinutes` of any learned time.
    static func isNear(_ date: Date, learned: [LearnedWalkTime], windowMinutes: Int,
                       calendar: Calendar = .current) -> Bool {
        let now = minutesSinceMidnight(of: date, calendar: calendar)
        return learned.contains { time in
            let raw = abs(now - time.minutesSinceMidnight)
            return min(raw, 24 * 60 - raw) <= windowMinutes
        }
    }

    /// Core Data wrapper: learns from walks logged over the lookback window.
    static func learnedTimes(context: NSManagedObjectContext,
                             home: HomeLocationStore = HomeLocationStore(),
                             calendar: Calendar = .current,
                             tuning: WalkDetectionTuning = .default,
                             now: Date = Date()) -> [LearnedWalkTime] {
        let from = now.addingTimeInterval(-TimeInterval(tuning.habitLookbackDays) * 24 * 60 * 60)
        let starts = WalkLogQuery.walkEntries(from: from, to: now, context: context, home: home)
            .map(\.performedAt)
        return learnedTimes(from: starts, calendar: calendar, tuning: tuning)
    }

    // MARK: - Private

    private static func habit(in clusterMinutes: [Int],
                              tuning: WalkDetectionTuning) -> LearnedWalkTime? {
        guard clusterMinutes.count >= tuning.habitMinSamples,
              let center = median(of: clusterMinutes) else { return nil }
        let kept = clusterMinutes.filter { abs($0 - center) <= tuning.habitSpreadMinutes }
        guard kept.count >= tuning.habitMinSamples, let time = median(of: kept) else {
            return nil
        }
        return LearnedWalkTime(hour: time / 60, minute: time % 60, sampleCount: kept.count)
    }

    private static func median(of values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func minutesSinceMidnight(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
