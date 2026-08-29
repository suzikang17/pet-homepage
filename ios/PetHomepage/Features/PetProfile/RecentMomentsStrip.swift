// ios/PetHomepage/Features/PetProfile/RecentMomentsStrip.swift
import SwiftUI

/// One tile in the strip: a photo's identity plus its thumbnail URL, once that has been resolved.
///
/// The strip takes these rather than `[Photo]` deliberately. Resolving a URL can mean an ImageIO
/// downsample and a disk write, and doing that inside `body` for up to 20 photos blocked Home's
/// first render entirely on a cold cache — the strip could not even render progressively.
/// `PetProfileView` now resolves them off the main thread and hands the results down; a tile
/// whose URL hasn't landed yet renders `PhotoThumbnail`'s own placeholder.
struct RecentMoment: Identifiable, Equatable {
    /// The `Photo`'s id — stable, so a resolve landing late updates the right tile.
    let id: UUID
    var url: URL?
}

/// Recent photos across every activity, newest first.
///
/// This is a separate section rather than part of the cadence grid on purpose. The grid is a
/// catalogue of things on a schedule; a walk has no cadence (`WalkActivityResolver` creates the
/// Walk type with `defaultIntervalDays: 0`, and the catalogue filters those out), so bending
/// the grid to admit it would change what the grid means. A strip lets walk photos reach Home
/// without that cost.
struct RecentMomentsStrip: View {
    let moments: [RecentMoment]
    let onTap: (() -> Void)?

    private let side: CGFloat = 88

    var body: some View {
        if !moments.isEmpty {
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
                        ForEach(moments) { moment in
                            PhotoThumbnail(url: moment.url, side: side, cornerRadius: 14)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .accessibilityIdentifier("recentMomentsStrip")
        }
    }
}
