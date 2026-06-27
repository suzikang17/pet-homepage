// ios/PetHomepage/Features/PetProfile/PhotoCropView.swift
import SwiftUI
import UIKit

/// Lets the user pan + pinch a picked photo to choose its focus, then renders just the
/// framed region (at the hero's aspect ratio) to JPEG. The stored image is pre-framed, so
/// displaying it elsewhere stays trivial.
struct PhotoCropView: View {
    let image: UIImage
    /// width / height of the crop window — matches the Home hero.
    var aspect: CGFloat = 1.5
    let onUse: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var displayWidth: CGFloat = 360

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            cropWindow(w: geo.size.width, h: geo.size.height)
                                .onAppear { displayWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, new in displayWidth = new }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 2))
                    .padding(.horizontal, 16)
                Text("Drag to move · pinch to zoom")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Frame photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let data = renderCrop(frameW: displayWidth) { onUse(data) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(Theme.primary)
        }
    }

    private func cropWindow(w: CGFloat, h: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: lastOffset.width + v.translation.width,
                                        height: lastOffset.height + v.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
                    .simultaneously(with:
                        MagnifyGesture()
                            .onChanged { v in scale = max(1, lastScale * v.magnification) }
                            .onEnded { _ in lastScale = scale }
                    )
            )
    }

    @MainActor
    private func renderCrop(frameW: CGFloat) -> Data? {
        let frameH = frameW / aspect
        let content = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: frameW, height: frameH)
            .clipped()
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(2, 1100 / frameW) // ~1100px-wide output
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }
}
