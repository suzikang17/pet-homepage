// ios/PetHomepage/Walk/WalkDetectorState.swift
import Foundation

/// Inputs to the walk-detection state machine. Emitted by the CoreLocation/CoreMotion shell
/// (WalkDetector); synthesized directly in tests.
enum WalkDetectorEvent: Equatable {
    case exitedHome(at: Date)
    case enteredHome(at: Date)
    /// One motion-activity sample. `isWalking` mirrors CMMotionActivity.walking.
    case walkingSample(at: Date, isWalking: Bool)
    /// The user tapped "Not now" on the prompt.
    case promptDismissed
}

/// What the shell should do in response to an event.
enum WalkDetectorEffect: Equatable {
    /// Fire the "looks like a walk — log it?" notification, backdating to the home exit.
    case promptStart(exitedAt: Date)
    /// Silently end the active session at the geofence crossing.
    case endSession(at: Date)
    case none
}

/// Pure reducer for walk detection — no CoreLocation/CoreMotion imports, fully unit-tested.
/// The shell reads `rule`, `hasActiveSession`, and `isNearScheduledSlot` fresh on each event
/// and passes them in.
struct WalkDetectorState: Equatable {
    private var awaySince: Date?
    private var walkingSince: Date?
    private var consecutiveNonWalking = 0
    private var promptedThisExcursion = false

    static let initial = WalkDetectorState()

    mutating func apply(_ event: WalkDetectorEvent, rule: WalkPromptRule,
                        hasActiveSession: Bool, isNearScheduledSlot: Bool,
                        tuning: WalkDetectionTuning) -> WalkDetectorEffect {
        switch event {
        case let .exitedHome(at):
            awaySince = at
            walkingSince = nil
            consecutiveNonWalking = 0
            promptedThisExcursion = false
            return .none

        case let .enteredHome(at):
            self = .initial
            return hasActiveSession ? .endSession(at: at) : .none

        case .promptDismissed:
            promptedThisExcursion = true
            return .none

        case let .walkingSample(at, isWalking):
            guard let awaySince else { return .none } // not on an excursion
            guard !hasActiveSession, !promptedThisExcursion, rule != .off else { return .none }
            if rule == .scheduledOnly, !isNearScheduledSlot { return .none }

            if isWalking {
                consecutiveNonWalking = 0
                if walkingSince == nil { walkingSince = at }
                if let since = walkingSince,
                   at.timeIntervalSince(since) >= tuning.sustainedWalkSeconds {
                    promptedThisExcursion = true
                    return .promptStart(exitedAt: awaySince)
                }
            } else {
                // One non-walking sample (crossing a street, sniffing a lamppost) is
                // absorbed; two in a row reset the sustained-walking window.
                consecutiveNonWalking += 1
                if consecutiveNonWalking >= 2 {
                    walkingSince = nil
                    consecutiveNonWalking = 0
                }
            }
            return .none
        }
    }
}
