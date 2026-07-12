// ios/PetHomepageWidgets/WalkActivityAttributes.swift
// Shared between the app target (which requests/ends the Live Activity) and the widget
// extension (which renders it) — both targets list this file in project.yml.
import ActivityKit
import Foundation

struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }

    var petName: String
}
