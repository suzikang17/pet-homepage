// ios/PetHomepageTests/PendingWalkPhotosTests.swift
import XCTest

@testable import PetHomepage

final class PendingWalkPhotosTests: XCTestCase {
    private var directory: URL!
    private var buffer: PendingWalkPhotos!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-tests-\(UUID().uuidString)")
        buffer = PendingWalkPhotos(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        buffer = nil
    }

    func testEmptyBufferReturnsNothing() {
        XCTAssertEqual(buffer.photos(for: UUID()).count, 0)
        XCTAssertEqual(buffer.count(for: UUID()), 0)
    }

    func testPreservesCaptureOrder() throws {
        let session = UUID()
        for byte in UInt8(1)...UInt8(12) {
            try buffer.add(Data([byte]), sessionID: session)
        }
        XCTAssertEqual(buffer.photos(for: session), (UInt8(1)...UInt8(12)).map { Data([$0]) })
    }

    func testSessionsAreIsolated() throws {
        let a = UUID(), b = UUID()
        try buffer.add(Data([1]), sessionID: a)
        try buffer.add(Data([2]), sessionID: b)
        XCTAssertEqual(buffer.photos(for: a), [Data([1])])
        XCTAssertEqual(buffer.photos(for: b), [Data([2])])
    }

    func testClearRemovesOnlyThatSession() throws {
        let a = UUID(), b = UUID()
        try buffer.add(Data([1]), sessionID: a)
        try buffer.add(Data([2]), sessionID: b)
        buffer.clear(sessionID: a)
        XCTAssertEqual(buffer.photos(for: a).count, 0)
        XCTAssertEqual(buffer.photos(for: b).count, 1)
    }

    /// The session survives app termination in UserDefaults, so its photos must survive too —
    /// which is why this buffer is on disk and not in memory. A fresh instance over the same
    /// directory stands in for a relaunch.
    func testSurvivesARelaunch() throws {
        let session = UUID()
        try buffer.add(Data([7]), sessionID: session)
        let reopened = PendingWalkPhotos(directory: directory)
        XCTAssertEqual(reopened.photos(for: session), [Data([7])])
    }
}
