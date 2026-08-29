// ios/PetHomepage/App/QuickActions.swift
import SwiftUI
import UIKit

/// Home-screen quick action ("Jot an idea" on the app icon's long-press menu) → the idea
/// scratchpad sheet. Same observable-router shape as `NotificationRouter`: the UIKit delegates
/// below set the flag, `ContentView` watches it and presents the sheet.
@Observable
final class QuickActionRouter {
    /// UIKit instantiates the delegates itself, so they can't be handed an instance — shared
    /// is the seam between them and the SwiftUI environment.
    static let shared = QuickActionRouter()
    var pendingJot = false
}

/// A pure-SwiftUI app has no app/scene delegate, but quick actions are delivered to nothing
/// else — this pair exists solely to catch them. Registration is dynamic
/// (`UIApplication.shortcutItems`) rather than Info.plist: project.yml generates its plist
/// from INFOPLIST_KEY_* build settings, which cannot express the plist array a static
/// shortcut needs. Dynamic items appear from the app's first run onward.
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    static let jotType = "pet.homepage.jotIdea"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: Self.jotType,
                localizedTitle: "Jot an idea",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "lightbulb")
            )
        ]
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Cold launch from the quick action: the item rides in on the connection options,
        // before any scene (or ContentView) exists — stash it now, the view catches up later.
        if options.shortcutItem?.type == Self.jotType {
            QuickActionRouter.shared.pendingJot = true
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Warm launch: app already running (or suspended) when the icon menu is used.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard shortcutItem.type == QuickActionAppDelegate.jotType else {
            completionHandler(false)
            return
        }
        QuickActionRouter.shared.pendingJot = true
        completionHandler(true)
    }
}
