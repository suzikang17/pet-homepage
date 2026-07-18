// ios/PetHomepage/Walk/WalkStartDecision.swift
import Foundation

/// How a detected walk should begin.
enum WalkStartMode: Equatable {
    /// Start logging silently against a matched scheduled walk slot (Live Activity + undo notice).
    case silentRoutine(taskID: UUID)
    /// Post the "log it?" prompt (off-schedule walk, or auto-start disabled).
    case prompt
}

/// Pure decision, split out from the CoreLocation/CoreMotion detector so it's unit-testable:
/// a scheduled-slot match auto-starts silently only when the setting is on; everything else
/// prompts.
enum WalkStartDecision {
    static func mode(matchingSlotTaskID: UUID?, autoStartScheduled: Bool) -> WalkStartMode {
        if let id = matchingSlotTaskID, autoStartScheduled {
            return .silentRoutine(taskID: id)
        }
        return .prompt
    }
}
