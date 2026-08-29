// ios/PetHomepage/Walk/RetroWalkClassifier.swift
import Foundation

/// One motion-activity interval from the historical query. A sample runs from its
/// `startDate` until the next sample's start (the last one until the interval end).
struct MotionSample: Equatable {
    let startDate: Date
    let isWalking: Bool
}

/// Decides, from CoreMotion *history*, whether an excursion contained a sustained walk.
/// This is the retroactive twin of WalkDetectorState's live rule: the live path needs the
/// app running to see samples arrive; this one runs on the brief return-home wake, when the
/// whole excursion is already queryable. Pure — the shell maps CMMotionActivity into
/// MotionSample and passes them in.
enum RetroWalkClassifier {
    /// True when the samples contain a walking run at least `tuning.sustainedWalkSeconds`
    /// long, measured wall-clock from the run's start — non-walking gaps shorter than
    /// `tuning.retroGapToleranceSeconds` are absorbed (crossings, sniffing stops), matching
    /// the live reducer's absorb-one-sample behavior; longer gaps reset the run.
    ///
    /// The qualifying run must begin within `tuning.retroWalkStartWindowSeconds` of
    /// `intervalStart` (the home exit): a dog walk starts at the door, and without this a
    /// grocery run with six minutes of aisle-walking would log as a door-to-door walk.
    static func sustainedWalk(in samples: [MotionSample], from intervalStart: Date,
                              until intervalEnd: Date,
                              tuning: WalkDetectionTuning = .default) -> Bool {
        let startDeadline = intervalStart.addingTimeInterval(tuning.retroWalkStartWindowSeconds)
        let ordered = samples.sorted { $0.startDate < $1.startDate }
        var runStart: Date?
        for (index, sample) in ordered.enumerated() {
            let segmentEnd = index + 1 < ordered.count
                ? ordered[index + 1].startDate : intervalEnd
            guard segmentEnd > sample.startDate else { continue }
            if sample.isWalking {
                let start = runStart ?? sample.startDate
                runStart = start
                if start <= startDeadline,
                   segmentEnd.timeIntervalSince(start) >= tuning.sustainedWalkSeconds {
                    return true
                }
            } else if segmentEnd.timeIntervalSince(sample.startDate)
                        > tuning.retroGapToleranceSeconds {
                runStart = nil
            }
        }
        return false
    }
}
