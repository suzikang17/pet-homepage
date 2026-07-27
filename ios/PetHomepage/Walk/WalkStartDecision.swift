// ios/PetHomepage/Walk/WalkStartDecision.swift
import Foundation

/// How a detected walk should begin.
enum WalkStartMode: Equatable {
    /// Start logging silently against a matched scheduled walk slot (Live Activity + undo notice).
    case silentRoutine(taskID: UUID)
    /// Start logging silently against a resolved activity type — an off-schedule walk (Live
    /// Activity + undo notice).
    case silentActivity(typeID: UUID)
    /// Post the "log it?" prompt (auto-log turned off, or nothing to log against).
    case prompt
}

/// Pure decision, split out from the CoreLocation/CoreMotion detector so it's unit-testable.
/// With auto-log on (the default) a detected walk starts logging silently — a scheduled-slot
/// match takes priority over the resolved activity type. With auto-log off, everything prompts.
enum WalkStartDecision {
    static func mode(matchingSlotTaskID: UUID?, resolvedTypeID: UUID?,
                     autoLog: Bool) -> WalkStartMode {
        guard autoLog else { return .prompt }
        if let taskID = matchingSlotTaskID { return .silentRoutine(taskID: taskID) }
        if let typeID = resolvedTypeID { return .silentActivity(typeID: typeID) }
        return .prompt
    }
}
