// ios/PetHomepage/Walk/WalkLiveActivityController.swift
import ActivityKit
import Foundation

/// Reconciles the lock-screen Live Activity with the persisted walk session. Called after
/// every session mutation (banner, notification actions, detector, expiry) — idempotent, so
/// callers never track what the current Activity state is.
enum WalkLiveActivityController {
    static func sync(active session: WalkSession?, petName: String) {
        Task {
            if let session {
                guard ActivityAuthorizationInfo().areActivitiesEnabled,
                      Activity<WalkActivityAttributes>.activities.isEmpty else { return }
                let attributes = WalkActivityAttributes(petName: petName)
                let state = WalkActivityAttributes.ContentState(startedAt: session.startedAt)
                _ = try? Activity.request(attributes: attributes,
                                          content: .init(state: state, staleDate: nil))
            } else {
                for activity in Activity<WalkActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
