// ios/PetHomepage/Features/Diary/DiaryEntryEditView.swift
import SwiftUI

struct DiaryEntryEditView: View {
    @State private var model: DiaryEntryEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: DiaryStore, editing: DiaryEntry?) {
        _model = State(initialValue: DiaryEntryEditViewModel(store: store, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Diary entry",
            systemImage: "book.fill",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { try? model.save(); dismiss() }
        ) {
            Section("When") {
                DatePicker("Date", selection: $model.date, displayedComponents: .date)
            }
            Section("Note") {
                TextField("What happened today…", text: $model.note, axis: .vertical)
                    .lineLimit(3...8)
            }
            PendingPhotoSection(
                existing: model.existingPhotos,
                pending: model.pendingPhotos,
                onPick: { model.addPickedPhoto($0) },
                onDeleteExisting: { model.deleteExisting($0) },
                onRemovePending: { model.removePending(at: $0) }
            )
        }
    }
}
