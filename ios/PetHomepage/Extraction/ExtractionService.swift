// ios/PetHomepage/Extraction/ExtractionService.swift
import Foundation

/// Where the AI extraction endpoint lives, plus the shared secret the route requires.
/// `secret` is sent as the `x-extract-secret` header; nil/empty omits it (the route 401s).
struct ExtractionConfig {
    let endpoint: URL
    let secret: String?
}

enum ExtractionError: Error, Equatable {
    case badStatus(Int)
    case emptyResults
}

/// Sends an uploaded record (file bytes + MIME type) to the extraction endpoint and
/// returns the structured events Claude parsed out. Injected everywhere so tests
/// never hit the network or a real Claude.
protocol ExtractionService {
    func extract(
        fileData: Data,
        mimeType: String,
        fileName: String,
        note: String?,
        date: String?
    ) async throws -> [ExtractionResult]
}

extension ExtractionService {
    /// Convenience: keep existing call sites working with sensible defaults.
    func extract(fileData: Data, mimeType: String) async throws -> [ExtractionResult] {
        try await extract(fileData: fileData, mimeType: mimeType,
                          fileName: "upload", note: nil, date: nil)
    }
}

/// Production adapter: POSTs JSON to a configurable URL, matching the /api/extract
/// route's ExtractRequestSchema: { fileName, mimeType, content (base64), note?, date? }.
/// The ONLY ExtractionService that touches URLSession.
final class URLSessionExtractionService: ExtractionService {
    private let config: ExtractionConfig
    private let session: URLSession

    init(config: ExtractionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func extract(
        fileData: Data,
        mimeType: String,
        fileName: String,
        note: String?,
        date: String?
    ) async throws -> [ExtractionResult] {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = config.secret, !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "x-extract-secret")
        }

        // Matches lib/schemas/extract-request.ts: { fileName, mimeType, content(base64), note?, date? }
        var payload: [String: Any] = [
            "fileName": fileName,
            "mimeType": mimeType,
            "content": fileData.base64EncodedString(),
        ]
        if let note { payload["note"] = note }
        if let date { payload["date"] = date }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ExtractionError.badStatus(http.statusCode)
        }
        let decoded = try ExtractionResult.decoder.decode(ExtractionResponse.self, from: data)
        if decoded.results.isEmpty { throw ExtractionError.emptyResults }
        return decoded.results
    }
}
