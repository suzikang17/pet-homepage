// ios/PetHomepage/DesignSystem/PhotoStripSection.swift
import PhotosUI
import SwiftUI
import UIKit

/// A reusable "Photos" Form section for record detail views: a multi-select picker that
/// downscales + persists each pick via `onAdd`, a horizontal strip of existing photos, and a
/// delete affordance. The record already exists, so photos attach immediately.
struct PhotoStripSection: View {
    let photos: [Photo]
    /// Persist one picked + downscaled JPEG to the owning record.
    let onAdd: (Data) -> Void
    let onDelete: (Photo) -> Void
    /// Called after a picker batch finishes so the parent can reload `photos`.
    let onReload: () -> Void

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
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            if let data = photo.imageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button { onDelete(photo) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.55))
                                                .font(.system(size: 18))
                                        }
                                        .padding(3)
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in load(items) }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onCapture: { image in
                if let jpeg = ImageDownscaler.scaledJPEG(from: image) {
                    onAdd(jpeg)
                    onReload()
                }
            }, onFinish: { showingCamera = false })
            .ignoresSafeArea()
        }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { continue }
                if let jpeg = ImageDownscaler.scaledJPEG(from: ui) {
                    await MainActor.run { onAdd(jpeg) }
                }
            }
            await MainActor.run {
                pickerItems = []
                onReload()
            }
        }
    }
}
