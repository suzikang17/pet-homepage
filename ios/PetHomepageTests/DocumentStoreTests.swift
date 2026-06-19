// ios/PetHomepageTests/DocumentStoreTests.swift
import XCTest
@testable import PetHomepage

final class DocumentStoreTests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    func testSaveThenReadRoundTrips() throws {
        let store = DocumentStore(baseURL: baseURL)
        let payload = Data("bloodwork".utf8)

        let url = try store.save(payload, named: "labs.pdf")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.read(named: "labs.pdf"), payload)
    }

    func testSaveCreatesMissingBaseDirectory() throws {
        let store = DocumentStore(baseURL: baseURL) // baseURL does not exist yet
        XCTAssertNoThrow(try store.save(Data("x".utf8), named: "a.txt"))
    }
}
