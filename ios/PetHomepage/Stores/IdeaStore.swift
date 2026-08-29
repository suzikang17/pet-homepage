// ios/PetHomepage/Stores/IdeaStore.swift
import Foundation

/// The seam that keeps a future Convex-backed store a drop-in replacement: views talk only to
/// this protocol, never to the file. Adding a `ConvexIdeaStore` must not require touching
/// `IdeaListView`.
///
/// `ideas()` and `markdownExport()` do not throw by design — a corrupt file degrades to an
/// empty scratchpad rather than surfacing an error the user cannot act on.
protocol IdeaStore {
    /// Newest first.
    func ideas() -> [Idea]
    /// Returns nil (without writing) when `text` is blank; throws only on a real write failure.
    @discardableResult
    func add(text: String, screen: String?) throws -> Idea?
    func delete(_ idea: Idea) throws
    func markdownExport() -> String
}

/// Persists the scratchpad as one JSON array, written atomically.
final class FileIdeaStore: IdeaStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let timeZone: TimeZone
    private let now: () -> Date

    init(directory: URL,
         fileManager: FileManager = .default,
         timeZone: TimeZone = .current,
         now: @escaping () -> Date = Date.init) {
        self.fileURL = directory.appendingPathComponent("ideas.json")
        self.fileManager = fileManager
        self.timeZone = timeZone
        self.now = now
    }

    /// Production: the app's private Documents directory.
    static func documents() -> FileIdeaStore {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileIdeaStore(directory: directory)
    }

    func ideas() -> [Idea] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([Idea].self, from: data) else {
            return [] // missing or corrupt: an empty scratchpad beats a crash
        }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(text: String, screen: String?) throws -> Idea? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let idea = Idea(id: UUID(), text: trimmed, createdAt: now(), screen: screen)
        try write(ideas() + [idea])
        return idea
    }

    func delete(_ idea: Idea) throws {
        try write(ideas().filter { $0.id != idea.id })
    }

    func markdownExport() -> String {
        let all = ideas()
        guard !all.isEmpty else { return "## Ideas — none captured" }
        let formatter = Self.stampFormatter(in: timeZone)
        let lines = all.map { idea in
            let context = [idea.screen, formatter.string(from: idea.createdAt)]
                .compactMap { $0 }
                .joined(separator: " · ")
            return "- **\(idea.text)** — \(context)"
        }
        return (["## Ideas — \(all.count) captured", ""] + lines).joined(separator: "\n")
    }

    /// Fixed POSIX locale and lowercase am/pm so the output is stable wherever the phone is set.
    private static func stampFormatter(in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }

    private func write(_ ideas: [Idea]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Self.encoder.encode(ideas).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
