// ios/PetHomepageTests/Support/FakeExtractionService.swift
import Foundation
@testable import PetHomepage

/// In-memory fake of ExtractionService for unit tests — no network, no real Claude.
/// Returns canned results (or throws a canned error) and records the last input.
final class FakeExtractionService: ExtractionService {
    var results: [ExtractionResult]
    var errorToThrow: Error?
    private(set) var lastFileData: Data?
    private(set) var lastMimeType: String?
    private(set) var callCount = 0

    init(results: [ExtractionResult] = [], errorToThrow: Error? = nil) {
        self.results = results
        self.errorToThrow = errorToThrow
    }

    func extract(fileData: Data, mimeType: String) async throws -> [ExtractionResult] {
        callCount += 1
        lastFileData = fileData
        lastMimeType = mimeType
        if let errorToThrow { throw errorToThrow }
        return results
    }
}
