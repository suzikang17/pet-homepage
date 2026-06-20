// ios/PetHomepageTests/Support/FakeMirrorService.swift
import Foundation
@testable import PetHomepage

/// In-memory fake of MirrorService — no network. Records every pushed snapshot so tests
/// can assert push count and contents, and can throw a canned error.
final class FakeMirrorService: MirrorService {
    var errorToThrow: Error?
    private(set) var pushedSnapshots: [MirrorSnapshot] = []
    private(set) var callCount = 0

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func push(_ snapshot: MirrorSnapshot) async throws {
        callCount += 1
        if let errorToThrow { throw errorToThrow }
        pushedSnapshots.append(snapshot)
    }
}
