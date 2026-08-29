// ios/PetHomepage/Walk/WatchWalkImportDecision.swift
import Foundation

/// A walk already in the log, reduced to its span for duplicate checks. `end` is nil for
/// entries logged without a duration (a bare check-off).
struct LoggedWalkSpan: Equatable {
    let start: Date
    let end: Date?
}

/// Decides whether a watch workout becomes a logged pet walk. Pure — the importer fetches
/// the nearby logged walks and the active session and passes their spans in.
enum WatchWalkImportDecision {
    static func shouldImport(workoutStart: Date, workoutEnd: Date,
                             importSince: Date?,
                             existingWalks: [LoggedWalkSpan],
                             activeSessionStart: Date?,
                             tuning: WalkDetectionTuning = .default) -> Bool {
        // Same bar as detection: shorter than a sustained walk isn't a dog walk.
        guard workoutEnd.timeIntervalSince(workoutStart) >= tuning.sustainedWalkSeconds
        else { return false }
        // No import-since date means import was never enabled — refuse rather than flood.
        guard let importSince, workoutEnd >= importSince else { return false }

        let tolerance = TimeInterval(tuning.watchImportOverlapToleranceMinutes * 60)
        let paddedStart = workoutStart.addingTimeInterval(-tolerance)
        let paddedEnd = workoutEnd.addingTimeInterval(tolerance)

        // A live session that began before the padded window closed will log this same walk
        // when it ends (its end is unknown, so treat it as open-ended).
        if let activeSessionStart, activeSessionStart <= paddedEnd { return false }

        for walk in existingWalks {
            let walkEnd = walk.end ?? walk.start
            if walk.start <= paddedEnd && walkEnd >= paddedStart { return false }
        }
        return true
    }
}
