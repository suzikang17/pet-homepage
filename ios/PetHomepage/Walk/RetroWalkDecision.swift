// ios/PetHomepage/Walk/RetroWalkDecision.swift
import Foundation

/// Gate run before the (comparatively expensive) motion-history query on returning home:
/// is this excursion even a candidate for retroactive walk detection? Pure and
/// unit-tested; WalkDetector reads the inputs fresh at the geofence-entry event.
enum RetroWalkDecision {
    static func shouldEvaluate(exitedAt: Date, enteredAt: Date,
                               hadActiveSession: Bool, promptDismissed: Bool,
                               rule: WalkPromptRule, isNearScheduledSlot: Bool,
                               tuning: WalkDetectionTuning = .default) -> Bool {
        // A live session already captured this excursion; "Not now" means not this one;
        // rule .off disarms detection entirely.
        guard !hadActiveSession, !promptDismissed, rule != .off else { return false }
        if rule == .scheduledOnly, !isNearScheduledSlot { return false }
        let away = enteredAt.timeIntervalSince(exitedAt)
        return away >= tuning.sustainedWalkSeconds && away <= tuning.maxRetroExcursionSeconds
    }
}
