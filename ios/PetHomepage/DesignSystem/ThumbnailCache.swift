// ios/PetHomepage/DesignSystem/ThumbnailCache.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Maximum pixel dimension for a cached thumbnail. Point sizes are pre-multiplied for @3x,
/// which is the worst case — a @2x device just loads a slightly oversized file.
enum ThumbSize: Int, CaseIterable {
    /// 44pt Timeline row thumbnail.
    case row = 132
    /// 88pt Home strip tile.
    case strip = 264
    /// UNNotificationAttachment — shown expanded, so larger, but not full size.
    case notification = 800
    /// Detail and Home hero headers.
    case hero = 1200
}

/// Downsampled JPEGs on disk, derived from `Photo.imageData` and addressed by file URL.
///
/// Two reasons this is files rather than an in-memory cache. Stored photos are 1600px at
/// quality 0.8 (see `ImageDownscaler`), roughly 200–500 KB each, and decoding one of those for
/// a 44pt row in a scrolling list drops frames. And `UNNotificationAttachment` requires a file
/// URL — it cannot take `Data` out of Core Data at all.
///
/// This is derived data and lives in Caches/, so iOS may evict it under storage pressure.
/// `Photo.imageData` remains the source of truth and every miss regenerates transparently.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo-thumbs", isDirectory: true)
    }

    /// The cached thumbnail's URL, generating it on a miss. `imageData` is an autoclosure so a
    /// hit never touches the Core Data blob.
    func url(forPhotoID id: UUID, size: ThumbSize,
             imageData: @autoclosure () -> Data?) -> URL? {
        let target = directory
            .appendingPathComponent("\(id.uuidString)@\(size.rawValue).jpg")
        if fileManager.fileExists(atPath: target.path) { return target }
        guard let data = imageData(),
              let thumbnail = Self.downsample(data, maxPixel: size.rawValue) else { return nil }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        guard Self.writeJPEG(thumbnail, to: target) else { return nil }
        return target
    }

    /// Convenience for a managed `Photo`. Call on the context's own thread.
    func url(for photo: Photo, size: ThumbSize) -> URL? {
        url(forPhotoID: photo.id, size: size, imageData: photo.imageData)
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honour EXIF orientation, or portrait shots come back sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return false }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination)
    }
}
