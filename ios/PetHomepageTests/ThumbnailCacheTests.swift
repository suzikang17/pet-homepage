// ios/PetHomepageTests/ThumbnailCacheTests.swift
import CoreData
import UIKit
import XCTest

@testable import PetHomepage

final class ThumbnailCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: ThumbnailCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-tests-\(UUID().uuidString)")
        cache = ThumbnailCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        cache = nil
    }

    /// A real JPEG, large enough that downsampling to 132px is a genuine reduction.
    private func sampleJPEG(side: CGFloat = 900) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side / 2, height: side / 2))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    func testGeneratesThumbnailAtRequestedSize() throws {
        let url = cache.url(forPhotoID: UUID(), size: .row, imageData: sampleJPEG())
        let unwrapped = try XCTUnwrap(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unwrapped.path))

        let image = try XCTUnwrap(UIImage(contentsOfFile: unwrapped.path))
        let longest = max(image.size.width, image.size.height) * image.scale
        XCTAssertLessThanOrEqual(Int(longest.rounded()), ThumbSize.row.rawValue)
    }

    func testSecondRequestReusesTheFileWithoutDecodingAgain() throws {
        let id = UUID()
        var decodeCount = 0
        func data() -> Data? {
            decodeCount += 1
            return sampleJPEG()
        }

        _ = cache.url(forPhotoID: id, size: .row, imageData: data())
        _ = cache.url(forPhotoID: id, size: .row, imageData: data())
        XCTAssertEqual(decodeCount, 1, "cached file was not reused")
    }

    /// The cache lives in Caches/ and iOS may evict it at any time. Every read path must
    /// regenerate silently rather than showing a hole.
    func testRegeneratesAfterEviction() throws {
        let id = UUID()
        let first = try XCTUnwrap(cache.url(forPhotoID: id, size: .row, imageData: sampleJPEG()))
        try FileManager.default.removeItem(at: first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))

        let second = try XCTUnwrap(cache.url(forPhotoID: id, size: .row, imageData: sampleJPEG()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(first, second, "regeneration should reuse the same path")
    }

    func testSizesGetSeparateFiles() throws {
        let id = UUID()
        let row = try XCTUnwrap(cache.url(forPhotoID: id, size: .row, imageData: sampleJPEG()))
        let strip = try XCTUnwrap(cache.url(forPhotoID: id, size: .strip, imageData: sampleJPEG()))
        XCTAssertNotEqual(row, strip)
    }

    func testNilImageDataReturnsNil() {
        XCTAssertNil(cache.url(forPhotoID: UUID(), size: .row, imageData: nil))
    }

    func testGarbageImageDataReturnsNil() {
        XCTAssertNil(cache.url(forPhotoID: UUID(), size: .row, imageData: Data([0x00, 0x01])))
    }

    // MARK: - Hit-only lookup

    /// The whole point of `cachedURL`: it must never generate. Main-thread `load()` paths call
    /// it for every row, and a generating variant there was seconds of blocked main thread on a
    /// cold cache.
    func testCachedURLNeverGenerates() {
        XCTAssertNil(cache.cachedURL(forPhotoID: UUID(), size: .row))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path),
                       "a miss must not even create the cache directory")
    }

    func testCachedURLFindsAnAlreadyGeneratedFile() throws {
        let id = UUID()
        let generated = try XCTUnwrap(cache.url(forPhotoID: id, size: .row,
                                                 imageData: sampleJPEG()))
        XCTAssertEqual(cache.cachedURL(forPhotoID: id, size: .row), generated)
        XCTAssertNil(cache.cachedURL(forPhotoID: id, size: .hero),
                     "a hit at one size is not a hit at another")
    }

    // MARK: - Async resolution

    func testResolveURLGeneratesTheSameFileAsTheSyncPath() async throws {
        let id = UUID()
        let resolved = try XCTUnwrap(await cache.resolveURL(forPhotoID: id, size: .row,
                                                             imageData: sampleJPEG()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
        XCTAssertEqual(cache.cachedURL(forPhotoID: id, size: .row), resolved)
    }

    /// Generation now runs on a background executor, so two surfaces can ask for the same
    /// (photo, size) at once. The staged write must leave one intact file, never a partial one
    /// that the loser then serves as a cache hit.
    func testConcurrentResolutionsOfTheSamePhotoAgree() async throws {
        let id = UUID()
        let data = sampleJPEG()
        async let first = cache.resolveURL(forPhotoID: id, size: .row, imageData: data)
        async let second = cache.resolveURL(forPhotoID: id, size: .row, imageData: data)
        async let third = cache.resolveURL(forPhotoID: id, size: .row, imageData: data)
        let a = await first
        let b = await second
        let c = await third
        let urls = [try XCTUnwrap(a), try XCTUnwrap(b), try XCTUnwrap(c)]
        XCTAssertEqual(Set(urls).count, 1)
        XCTAssertNotNil(UIImage(contentsOfFile: urls[0].path), "the cached file must be readable")
        let leftovers = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tmp" }
        XCTAssertEqual(leftovers, [], "scratch files must not be left behind")
    }

    // MARK: - Photo.id hazard

    /// `Photo.id` is declared non-optional in Swift but is `optional="YES"` in the Core Data
    /// model — CloudKit mirroring requires it, and no schema change is possible here. Thumbnails
    /// put that read on Home's and the Timeline's main load path, so a record that cannot answer
    /// must be treated like one with no thumbnail rather than trapping the app on its first
    /// screen.
    func testIdentifierRejectsRecordsThatCannotAnswer() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        let logStore = LogStore(context: context, petStore: petStore)
        let activityStore = ActivityStore(context: context, petStore: petStore)
        let type = try activityStore.createType(name: "Bath", category: .care,
                                                iconName: "shower", defaultIntervalDays: 30)
        let entry = try logStore.logActivity(type: type, performedAt: Date(), note: nil,
                                             intervalDays: 30)
        let photo = try logStore.addPhoto(to: entry, imageData: sampleJPEG())

        XCTAssertEqual(ThumbnailCache.identifier(of: photo), photo.id)

        context.delete(photo)
        XCTAssertNil(ThumbnailCache.identifier(of: photo),
                     "a deleted record has no thumbnail, and asking must not raise")
        XCTAssertNil(cache.url(for: photo, size: .row))
        XCTAssertNil(cache.cachedURL(for: photo, size: .row))
    }
}
