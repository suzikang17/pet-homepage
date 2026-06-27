// ios/PetHomepage/DesignSystem/ContactPicker.swift
import ContactsUI
import SwiftUI

/// The system contact picker. No Contacts permission is required — it runs out-of-process and
/// hands back only the single contact the user explicitly taps.
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
