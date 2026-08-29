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
///
/// Threading: generation may run on any thread (see `resolveURL`), so the write is staged
/// through a scratch file and moved into place. Every stored property is immutable and
/// `FileManager` is safe for these operations, hence `@unchecked Sendable`.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo-thumbs", isDirectory: true)
    }

    private func path(forPhotoID id: UUID, size: ThumbSize) -> URL {
        directory.appendingPathComponent("\(id.uuidString)@\(size.rawValue).jpg")
    }

    /// The cached thumbnail's URL, generating it on a miss. `imageData` is an autoclosure so a
    /// hit never touches the Core Data blob.
    ///
    /// A miss is EXPENSIVE — a blob fault, an ImageIO downsample and a JPEG write — so this must
    /// not be called from a view body or a main-thread `load()`. Those paths use
    /// `cachedURL(forPhotoID:size:)` for the free hit and `resolveURL(...)` for the miss.
    func url(forPhotoID id: UUID, size: ThumbSize,
             imageData: @autoclosure () -> Data?) -> URL? {
        let target = path(forPhotoID: id, size: size)
        if fileManager.fileExists(atPath: target.path) { return target }
        guard let data = imageData(),
              let thumbnail = Self.downsample(data, maxPixel: size.rawValue) else { return nil }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        // Staged through a uniquely-named scratch file rather than written at the destination
        // directly. Generation now happens on a background executor and two surfaces can ask
        // for the same (photo, size) at once; a half-written JPEG sitting at the real path
        // would be handed to the other caller as a cache hit.
        let scratch = directory.appendingPathComponent(
            "\(id.uuidString)@\(size.rawValue).\(UUID().uuidString).tmp")
        guard Self.writeJPEG(thumbnail, to: scratch) else {
            try? fileManager.removeItem(at: scratch)
            return nil
        }
        do {
            try fileManager.moveItem(at: scratch, to: target)
        } catch {
            try? fileManager.removeItem(at: scratch)
            // Losing the race is a success: the winner's file is at the same path and holds
            // the same bytes, derived from the same source photo.
            return fileManager.fileExists(atPath: target.path) ? target : nil
        }
        return target
    }

    /// Convenience for a managed `Photo`. Call on the context's own thread.
    func url(for photo: Photo, size: ThumbSize) -> URL? {
        guard let id = Self.identifier(of: photo) else { return nil }
        return url(forPhotoID: id, size: size, imageData: photo.imageData)
    }

    /// The cached thumbnail's URL only if it is ALREADY on disk. A single `stat` — it never
    /// faults `Photo.imageData`, never downsamples and never writes.
    ///
    /// This is what lets a main-thread `load()` stay as cheap as it was before thumbnails
    /// existed: it answers every warm-cache row for free and hands only the misses to
    /// `resolveURL(for:size:)`.
    func cachedURL(forPhotoID id: UUID, size: ThumbSize) -> URL? {
        let target = path(forPhotoID: id, size: size)
        return fileManager.fileExists(atPath: target.path) ? target : nil
    }

    /// Cache-hit-only lookup for a managed `Photo`. Call on the context's own thread.
    func cachedURL(for photo: Photo, size: ThumbSize) -> URL? {
        guard let id = Self.identifier(of: photo) else { return nil }
        return cachedURL(forPhotoID: id, size: size)
    }

    /// Resolves the thumbnail without blocking the calling thread on the generation: a hit
    /// returns after one `stat`, a miss hands the ImageIO downsample and the JPEG write to a
    /// background executor and suspends until they finish.
    ///
    /// `imageData` is plain `Data` rather than the autoclosure the synchronous variant takes,
    /// deliberately. The blob has to be faulted on the managed object's own thread — `Photo` is
    /// not `Sendable` and must never cross an actor boundary — so the caller reads the bytes
    /// first and only the bytes travel.
    func resolveURL(forPhotoID id: UUID, size: ThumbSize, imageData: Data) async -> URL? {
        if let hit = cachedURL(forPhotoID: id, size: size) { return hit }
        return await Task.detached(priority: .userInitiated) { [self] in
            url(forPhotoID: id, size: size, imageData: imageData)
        }.value
    }

    /// Resolves a managed `Photo`'s thumbnail without blocking on the generation.
    ///
    /// The id and the blob are read here, synchronously, and only the bytes are handed off; a
    /// hit costs one `stat` and never touches the blob at all.
    ///
    /// `@MainActor` is load-bearing, not decoration. This app's only context is the main-queue
    /// `viewContext`, and a *nonisolated* `async` method is run on the generic executor even when
    /// its caller is on the main actor — which would fault a managed object off its own context's
    /// thread. The isolation pins the Core Data reads to the main actor; only
    /// `resolveURL(forPhotoID:size:imageData:)`, which touches no managed object, runs elsewhere.
    @MainActor
    func resolveURL(for photo: Photo, size: ThumbSize) async -> URL? {
        guard let id = Self.identifier(of: photo) else { return nil }
        if let hit = cachedURL(forPhotoID: id, size: size) { return hit }
        guard let data = photo.imageData else { return nil }
        return await resolveURL(forPhotoID: id, size: size, imageData: data)
    }

    /// A photo's id, read defensively.
    ///
    /// `Photo.id` is declared `@NSManaged public var id: UUID`, but the Core Data model marks
    /// the attribute `optional="YES"` — CloudKit mirroring requires every attribute to be
    /// optional, and no schema change is possible here. Reading the non-optional accessor on a
    /// record whose `id` really is nil (a partially-synced CloudKit row, or one written by a
    /// different client version) traps. Thumbnails put that read on the main load path of both
    /// Home and the Timeline, so it goes through KVC instead and a record that cannot answer is
    /// treated exactly like one with no thumbnail. Deleted and context-less objects are rejected
    /// first, because reading any property of those raises rather than returning nil.
    static func identifier(of photo: Photo) -> UUID? {
        guard !photo.isDeleted, photo.managedObjectContext != nil else { return nil }
        return photo.value(forKey: "id") as? UUID
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
