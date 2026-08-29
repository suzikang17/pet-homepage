// ios/PetHomepage/DesignSystem/ShakeDetector.swift
import SwiftUI
import UIKit

/// Shake-to-capture for the idea scratchpad, attachable as a `.background()` on any view.
///
/// A first-responder view controller is the only sound way to observe `motionEnded` from
/// SwiftUI. The widely-copied alternative — overriding `motionEnded` in a `UIWindow` extension —
/// is undefined behaviour in Swift (a method override in an extension); it happens to work
/// today and must not be built on.
///
/// Known and accepted: shake is also iOS's shake-to-undo gesture. While a text field holds
/// first-responder status the system undo alert wins and this never fires. Shaking mid-typing
/// is not a real workflow, and suppressing system undo app-wide costs more than the conflict.
struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        let controller = ShakeViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeViewController, context: Context) {
        controller.onShake = onShake
    }

    final class ShakeViewController: UIViewController {
        var onShake: (() -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else {
                super.motionEnded(motion, with: event)
                return
            }
            onShake?()
        }
    }
}
