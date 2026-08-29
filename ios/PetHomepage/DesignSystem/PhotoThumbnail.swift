// ios/PetHomepage/DesignSystem/PhotoThumbnail.swift
import SwiftUI
import UIKit

/// Renders a cached thumbnail from a file URL, off the main thread.
///
/// Takes a URL rather than a `Photo` deliberately: that keeps it free of Core Data and usable
/// from every surface, including ones holding only a value type.
struct PhotoThumbnail: View {
    let url: URL?
    let side: CGFloat
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        shape
            .fill(Theme.primary.opacity(0.08))
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(shape)
                }
            }
            .task(id: url) { await load() }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
        // The URL may have changed while decoding; `task(id:)` cancels, but check anyway.
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
