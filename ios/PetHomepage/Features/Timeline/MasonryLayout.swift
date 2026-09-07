// ios/PetHomepage/Features/Timeline/MasonryLayout.swift
import Foundation
import ImageIO

/// Distributes items into columns of near-equal height — the arithmetic behind the photo grid,
/// kept separate from the view so it can be tested without rendering anything.
///
/// A uniform grid crops every photo to the same square. Pets are photographed in both
/// orientations and a square crop throws away most of a portrait shot, so cells keep their own
/// aspect ratio and the columns absorb the resulting unevenness.
enum MasonryLayout {
    /// Places each item into whichever column is currently shortest, left to right on ties.
    ///
    /// Greedy rather than optimal on purpose: it is stable (a photo never moves because a LATER
    /// photo arrived), and the grid is newest-first, so appending tomorrow's photo must not
    /// reshuffle what is already on screen. An optimal partition has neither property.
    ///
    /// `heights` are relative — a cell's height for one unit of width, i.e. 1 / aspectRatio.
    /// Returns one array of item indices per column.
    static func columns<T>(_ items: [T], count: Int, height: (T) -> Double) -> [[Int]] {
        guard count > 0 else { return [] }
        var buckets: [[Int]] = Array(repeating: [], count: count)
        var totals = [Double](repeating: 0, count: count)

        for (index, item) in items.enumerated() {
            // `min(by:)` returns the FIRST minimum, so equal columns fill left to right and an
            // all-equal grid (every photo the same shape) lays out exactly like a plain grid.
            var shortest = 0
            for column in 1..<count where totals[column] < totals[shortest] { shortest = column }
            buckets[shortest].append(index)
            // A non-finite or non-positive ratio would poison the running total and pin every
            // subsequent photo into one column; treat it as square, which is what an unmeasured
            // photo renders as anyway.
            let h = height(item)
            totals[shortest] += (h.isFinite && h > 0) ? h : 1
        }
        return buckets
    }
}

/// Aspect ratios for photos, measured once and remembered.
///
/// The `Photo` entity stores no pixel dimensions, and adding them would mean a Core Data change
/// — which on this app means pushing a CloudKit dev schema from a Mac and promoting it in the
/// console. Far too much for a layout hint. So the ratio is measured instead, via
/// `CGImageSourceCopyPropertiesAtIndex`: image PROPERTIES only, never a decode of the pixels.
///
/// An unmeasured photo reports 1 (square), which is exactly what the old uniform grid drew, so
/// first paint is a plain grid that settles as measurements land.
actor AspectRatioCache {
    static let shared = AspectRatioCache()

    /// width / height, keyed by photo id.
    private var ratios: [UUID: Double] = [:]

    func ratio(for id: UUID) -> Double? { ratios[id] }

    /// Measures `data` and remembers the result. Returns nil when it carries no usable
    /// dimensions, in which case the caller keeps the square placeholder.
    @discardableResult
    func measure(id: UUID, data: Data) -> Double? {
        if let known = ratios[id] { return known }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        // Orientation 5–8 mean the stored pixels are rotated a quarter turn, so the DISPLAYED
        // shape is the transpose of the stored one. Without this a portrait photo saved as
        // landscape-plus-rotation gets a landscape cell and renders letterboxed.
        let quarterTurned = (properties[kCGImagePropertyOrientation] as? Int).map { $0 >= 5 } ?? false
        let ratio = quarterTurned ? height / width : width / height
        ratios[id] = ratio
        return ratio
    }
}
