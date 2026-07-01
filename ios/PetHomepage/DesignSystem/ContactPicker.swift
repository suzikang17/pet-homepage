// ios/PetHomepage/DesignSystem/ContactPicker.swift
import ContactsUI
import SwiftUI

/// Presents the system contact picker. `CNContactPickerViewController` must be *presented by* a
/// real UIViewController — embedding it directly as a SwiftUI sheet's root view controller silently
/// drops its delegate callbacks (you pick a contact and nothing happens). So this is an invisible
/// host that presents the picker when `isPresented` flips true, and clears the flag when it closes.
/// Attach it with `.background(ContactPicker(isPresented:onPick:))`, not `.sheet`.
///
/// No Contacts permission is required — the picker runs out-of-process and returns only the single
/// contact the user taps.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.onPick = onPick
        guard isPresented, !context.coordinator.isPresenting else {
            return
        }
        context.coordinator.isPresenting = true
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Present on the next runloop tick so `host` is guaranteed in the window hierarchy.
        DispatchQueue.main.async {
            var top: UIViewController = host
            while let presented = top.presentedViewController { top = presented }
            top.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let parent: ContactPicker
        var onPick: (CNContact) -> Void
        var isPresenting = false

        init(_ parent: ContactPicker) {
            self.parent = parent
            self.onPick = parent.onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
            finish()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finish()
        }

        /// The picker dismisses itself; just clear our state + the presenting flag.
        private func finish() {
            isPresenting = false
            parent.isPresented = false
        }
    }
}
