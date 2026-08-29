// ios/PetHomepage/Features/PetProfile/RecentMomentsStrip.swift
import SwiftUI

/// Recent photos across every activity, newest first.
///
/// This is a separate section rather than part of the cadence grid on purpose. The grid is a
/// catalogue of things on a schedule; a walk has no cadence (`WalkActivityResolver` creates the
/// Walk type with `defaultIntervalDays: 0`, and the catalogue filters those out), so bending
/// the grid to admit it would change what the grid means. A strip lets walk photos reach Home
/// without that cost.
struct RecentMomentsStrip: View {
    let photos: [Photo]
    let onTap: (() -> Void)?

    private let side: CGFloat = 88

    var body: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent moments")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    if let onTap {
                        Button("See all", action: onTap)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            PhotoThumbnail(
                                url: ThumbnailCache.shared.url(for: photo, size: .strip),
                                side: side,
                                cornerRadius: 14
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .accessibilityIdentifier("recentMomentsStrip")
        }
    }
}
