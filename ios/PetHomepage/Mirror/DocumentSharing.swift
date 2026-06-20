// ios/PetHomepage/Mirror/DocumentSharing.swift
import Foundation

/// A stored attachment, identified by its file name within the DocumentStore container.
/// (v1: file name is the reference — richer metadata can come later without changing callers.)
struct AttachmentReference: Equatable {
    let fileName: String
}

enum DocumentSharingError: Error, Equatable {
    /// No file exists for the reference's name in the DocumentStore container.
    case fileMissing(String)
}

/// Turns a stored attachment reference into the iCloud Drive file URL the system share sheet
/// consumes. Pure URL/logic — UIActivityViewController/ShareLink live in the View layer only.
final class DocumentSharing {
    private let documentStore: DocumentStore
    private let fileManager: FileManager

    init(documentStore: DocumentStore, fileManager: FileManager = .default) {
        self.documentStore = documentStore
        self.fileManager = fileManager
    }

    /// The on-disk (iCloud Drive in production) URL for a reference, or `.fileMissing` if absent.
    func shareURL(for reference: AttachmentReference) throws -> URL {
        let url = documentStore.fileURL(named: reference.fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DocumentSharingError.fileMissing(reference.fileName)
        }
        return url
    }

    /// From a candidate list of names, the references whose files actually exist — drives the
    /// Settings "browse documents" list without ever surfacing a dead share target.
    func availableReferences(named names: [String]) -> [AttachmentReference] {
        names
            .map { AttachmentReference(fileName: $0) }
            .filter { fileManager.fileExists(atPath: documentStore.fileURL(named: $0.fileName).path) }
    }
}
