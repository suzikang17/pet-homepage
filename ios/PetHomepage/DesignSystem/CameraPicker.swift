// ios/PetHomepage/DesignSystem/CameraPicker.swift
import SwiftUI
import UIKit

/// SwiftUI wrapper over UIImagePickerController's camera source — SwiftUI's PhotosPicker is
/// library-only, so camera capture needs this. Present it as a `.fullScreenCover` (the camera
/// needs the full screen; presenting it in a plain `.sheet` — especially nested inside another
/// sheet — makes it collapse immediately). Dismissal is explicit via `onFinish`, which the caller
/// wires to flip the presenting binding (relying on `@Environment(\.dismiss)` inside a
/// representable is unreliable).
struct CameraPicker: UIViewControllerRepresentable {
    /// Whether the device actually has a camera (false on Simulator). Callers gate the button on this.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onCapture: (UIImage) -> Void
    /// Called after the user captures or cancels — the caller dismisses the presentation here.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish()
        }
    }
}
