// ios/PetHomepage/Walk/WalkDetectionTuning.swift
import Foundation

/// Every detection threshold in one place — these are the knobs TestFlight feedback tunes.
struct WalkDetectionTuning {
    /// Continuous walking required after leaving home before the prompt fires.
    var sustainedWalkSeconds: TimeInterval = 4 * 60
    /// Radius of the home geofence region.
    var homeRadiusMeters: Double = 100
    /// A detected walk attaches to an open routine walk slot scheduled within this window.
    var slotAttachWindowMinutes: Int = 90
    /// "Only near scheduled walks" prompt rule: how far from a slot still counts as near.
    var scheduledPromptWindowMinutes: Int = 60
    /// Retroactive detection (motion history checked on returning home): a non-walking gap
    /// this short doesn't break a sustained-walking run — waiting at a crossing, a long sniff.
    var retroGapToleranceSeconds: TimeInterval = 90
    /// Retroactive detection ignores excursions longer than this: an all-day absence with
    /// some walking in it (commute, errands) is not a dog walk from door to door.
    var maxRetroExcursionSeconds: TimeInterval = 4 * 60 * 60
    /// A retro walk's sustained run must begin within this window of leaving home — dog
    /// walks start at the door (with room for a neighbor chat), while walking that begins
    /// deep into an excursion is a store or an office, not a walk.
    var retroWalkStartWindowSeconds: TimeInterval = 15 * 60
    /// Watch import: a workout overlapping an already-logged walk within this padding is a
    /// duplicate (the phone detected the same walk, or the user logged it by hand).
    var watchImportOverlapToleranceMinutes: Int = 30
    /// Sustained walking required when the home exit lands near an EXPECTED walk time (a
    /// scheduled slot or a learned habit): the prior does the confirming, so the timer and
    /// "Walk started" notice can appear fast instead of waiting out the full threshold.
    var fastConfirmSeconds: TimeInterval = 90
    /// Habit learning looks at logged walks over this many trailing days.
    var habitLookbackDays: Int = 30
    /// A time-of-day cluster needs this many walks landing near its median to be a habit.
    var habitMinSamples: Int = 4
    /// How far from the cluster median a walk can start and still support the habit.
    var habitSpreadMinutes: Int = 45
    /// A home exit within this window of a learned habit time gets the fast confirm.
    var habitPriorWindowMinutes: Int = 45
    /// Suggest re-timing a walk slot when its scheduled time drifts further than this from
    /// the learned habit.
    var habitSuggestDriftMinutes: Int = 30

    static let `default` = WalkDetectionTuning()
}

/// When the "log this walk?" prompt is allowed to fire.
enum WalkPromptRule: String, Codable, CaseIterable {
    case anyWalk
    case scheduledOnly
    case off

    var displayName: String {
        switch self {
        case .anyWalk: "Any sustained walk"
        case .scheduledOnly: "Only near scheduled walks"
        case .off: "Off"
        }
    }
}
