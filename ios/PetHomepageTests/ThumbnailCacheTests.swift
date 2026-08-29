// ios/PetHomepageTests/ThumbnailCacheTests.swift
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
}
