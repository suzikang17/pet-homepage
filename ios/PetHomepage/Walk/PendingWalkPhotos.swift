// ios/PetHomepage/Walk/PendingWalkPhotos.swift
import Foundation

/// JPEGs captured during a live walk, held until the session's `LogEntry` exists.
///
/// A walk in progress has no `LogEntry` — `WalkSession` lives in UserDefaults and the entry is
/// written only at `end()`. So a mid-walk capture has nothing to attach to and must be parked
/// somewhere until then.
///
/// On disk rather than in memory, and in Application Support rather than Caches: the session
/// itself survives app termination, so its photos must survive alongside it, and unlike
/// `ThumbnailCache` these are NOT derived data — evicting them loses the only copy.
struct PendingWalkPhotos {
    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending-walk-photos", isDirectory: true)
    }

    private func folder(for sessionID: UUID) -> URL {
        directory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Files are named by a zero-padded index so a lexicographic sort is capture order.
    func add(_ jpeg: Data, sessionID: UUID) throws {
        let folder = folder(for: sessionID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = count(for: sessionID)
        let name = String(format: "%06d.jpg", index)
        try jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    /// Buffered JPEGs in capture order, oldest first.
    ///
    /// Materialises every file at once, so this is for small buffers and for tests. The drain in
    /// `WalkSessionStore.writeEntry` iterates `fileURLs(for:)` and reads one JPEG at a time
    /// instead: nothing caps how many captures a walk may buffer, each is a 1600px q0.8 JPEG
    /// (200–500 KB), and 100 of them in a single `[Data]` is ~40 MB allocated up front — a
    /// plausible jetsam kill on an older device, right before the writes that would have
    /// emptied the buffer.
    func photos(for sessionID: UUID) -> [Data] {
        fileURLs(for: sessionID).compactMap { try? Data(contentsOf: $0) }
    }

    /// Drops one buffered file. Used as each capture is successfully attached, so a drain that
    /// fails part-way through leaves behind exactly the captures that did NOT attach.
    func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    func count(for sessionID: UUID) -> Int {
        fileURLs(for: sessionID).count
    }

    func clear(sessionID: UUID) {
        try? fileManager.removeItem(at: folder(for: sessionID))
    }

    /// Buffered files in capture order, oldest first. Read and remove them one at a time so
    /// peak memory is one photo rather than the whole walk.
    func fileURLs(for sessionID: UUID) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: folder(for: sessionID), includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
