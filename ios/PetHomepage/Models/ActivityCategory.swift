import Foundation

/// The fixed, app-defined grouping for activity types. Unlike `ActivityType` (user-defined,
/// editable), categories are a small stable set — so this mirrors `MarkerType`: a String-backed
/// enum stored as `categoryRaw` with an `.other` fallback for unknown values.
enum ActivityCategory: String, CaseIterable, Identifiable {
    case care
    case play
    case feeding
    case training
    case health
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .care: "Care"
        case .play: "Play"
        case .feeding: "Feeding"
        case .training: "Training"
        case .health: "Health"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .care: "heart"
        case .play: "tennisball"
        case .feeding: "fork.knife"
        case .training: "figure.walk"
        case .health: "cross.case"
        case .other: "pawprint"
        }
    }

    /// Strongly-typed view of a raw value; falls back to `.other` for unknown strings.
    init(rawValueOrOther raw: String) {
        self = ActivityCategory(rawValue: raw) ?? .other
    }
}
