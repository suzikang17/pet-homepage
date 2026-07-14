// ios/PetHomepage/DesignSystem/PendingPhotoSection.swift
import PhotosUI
import SwiftUI
import UIKit

/// A "Photos" Form section for EDIT sheets where the record may not exist yet. Shows already-
/// attached photos plus newly-picked-but-unsaved photos, with delete. Picks are downscaled to
/// Data and handed to `onPick`; the parent attaches them on save.
struct PendingPhotoSection: View {
    let existing: [Photo]
    let pending: [Data]
    let onPick: (Data) -> Void
    let onDeleteExisting: (Photo) -> Void
    let onRemovePending: (Int) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false

    var body: some View {
        Section("Photos") {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Add photos", systemImage: "photo.on.rectangle")
            }
            if CameraPicker.isAvailable {
                Button { showingCamera = true } label: {
                    Label("Take photo", systemImage: "camera")
                }
            }
            if !existing.isEmpty || !pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(existing) { photo in
                            thumb(photo.imageData) { onDeleteExisting(photo) }
                        }
                        ForEach(Array(pending.enumerated()), id: \.offset) { index, data in
                            thumb(data) { onRemovePending(index) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in load(items) }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onCapture: { image in
                if let jpeg = ImageDownscaler.scaledJPEG(from: image) { onPick(jpeg) }
            }, onFinish: { showingCamera = false })
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func thumb(_ data: Data?, onDelete: @escaping () -> Void) -> some View {
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("pendingPhotoThumb")
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

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { continue }
                if let jpeg = ImageDownscaler.scaledJPEG(from: ui) {
                    await MainActor.run { onPick(jpeg) }
                }
            }
            await MainActor.run { pickerItems = [] }
        }
    }
}
