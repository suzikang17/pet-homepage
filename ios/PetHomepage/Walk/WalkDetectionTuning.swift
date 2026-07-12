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
