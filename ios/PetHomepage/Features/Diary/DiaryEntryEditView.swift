// ios/PetHomepage/Features/Diary/DiaryEntryEditView.swift
import PhotosUI
import SwiftUI
import UIKit

struct DiaryEntryEditView: View {
    @State private var model: DiaryEntryEditViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
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
            Section("Photos") {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add photos", systemImage: "photo.on.rectangle")
                }
                if model.photoCount > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.existingPhotos) { photo in
                                thumb(photo.imageData) { model.deleteExisting(photo) }
                            }
                            ForEach(Array(model.pendingPhotos.enumerated()), id: \.offset) { index, data in
                                thumb(data) { model.removePending(at: index) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
    }

    @ViewBuilder
    private func thumb(_ data: Data?, onDelete: @escaping () -> Void) -> some View {
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable().scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .font(.system(size: 18))
                    }
                    .padding(3)
                }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { continue }
                let scaled = ui.preparingThumbnail(of: CGSize(width: 1600, height: 1600)) ?? ui
                if let jpeg = scaled.jpegData(compressionQuality: 0.8) {
                    await MainActor.run { model.addPickedPhoto(jpeg) }
                }
            }
            await MainActor.run { pickerItems = [] }
        }
    }
}
