// ios/PetHomepageTests/DocumentSharingTests.swift
import XCTest
@testable import PetHomepage

final class DocumentSharingTests: XCTestCase {
    private var baseURL: URL!
    private var documentStore: DocumentStore!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        documentStore = DocumentStore(baseURL: baseURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    func testShareURLReturnsExistingFileURL() throws {
        let url = try documentStore.save(Data("bloodwork".utf8), named: "labs.pdf")
        let sharing = DocumentSharing(documentStore: documentStore)

        let shareURL = try sharing.shareURL(for: AttachmentReference(fileName: "labs.pdf"))

        XCTAssertEqual(shareURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shareURL.path))
    }

    func testShareURLThrowsWhenFileMissing() {
        let sharing = DocumentSharing(documentStore: documentStore)
        XCTAssertThrowsError(try sharing.shareURL(for: AttachmentReference(fileName: "nope.pdf"))) { error in
            XCTAssertEqual(error as? DocumentSharingError, .fileMissing("nope.pdf"))
        }
    }

    func testAvailableReferencesFiltersToExistingFiles() throws {
        try documentStore.save(Data("a".utf8), named: "a.pdf")
        try documentStore.save(Data("b".utf8), named: "b.pdf")
        let sharing = DocumentSharing(documentStore: documentStore)

        let refs = sharing.availableReferences(named: ["a.pdf", "missing.pdf", "b.pdf"])

        XCTAssertEqual(refs, [AttachmentReference(fileName: "a.pdf"),
                              AttachmentReference(fileName: "b.pdf")])
    }
}
