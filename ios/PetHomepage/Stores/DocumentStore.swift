// ios/PetHomepage/Stores/DocumentStore.swift
import Foundation

final class DocumentStore {
    private let baseURL: URL
    private let fileManager: FileManager

    init(baseURL: URL, fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.fileManager = fileManager
    }

    /// Production: the app's iCloud Drive Documents folder (visible in Files/Finder).
    /// Returns nil if the user is not signed into iCloud.
    static func iCloudDrive() -> DocumentStore? {
        guard let container = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else { return nil }
        return DocumentStore(baseURL: container)
    }

    func fileURL(named name: String) -> URL {
        baseURL.appendingPathComponent(name)
    }

    @discardableResult
    func save(_ data: Data, named name: String) throws -> URL {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let url = fileURL(named: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func read(named name: String) throws -> Data {
        try Data(contentsOf: fileURL(named: name))
    }
}
