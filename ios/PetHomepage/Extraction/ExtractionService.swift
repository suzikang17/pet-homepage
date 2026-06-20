// ios/PetHomepage/Extraction/ExtractionService.swift
import Foundation

/// Where the AI extraction endpoint lives. The server `/api/extract` is DEFERRED —
/// this client is built entirely against the protocol below (tests use a fake).
struct ExtractionConfig {
    let endpoint: URL
}

enum ExtractionError: Error, Equatable {
    case badStatus(Int)
    case emptyResults
}

/// Sends an uploaded record (file bytes + MIME type) to the extraction endpoint and
/// returns the structured events Claude parsed out. Injected everywhere so tests
/// never hit the network or a real Claude.
protocol ExtractionService {
    func extract(fileData: Data, mimeType: String) async throws -> [ExtractionResult]
}

/// Production adapter: POSTs multipart/form-data to a configurable URL.
/// The ONLY ExtractionService that touches URLSession.
final class URLSessionExtractionService: ExtractionService {
    private let config: ExtractionConfig
    private let session: URLSession

    init(config: ExtractionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func extract(fileData: Data, mimeType: String) async throws -> [ExtractionResult] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(fileData: fileData, mimeType: mimeType, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ExtractionError.badStatus(http.statusCode)
        }
        let decoded = try ExtractionResult.decoder.decode(ExtractionResponse.self, from: data)
        return decoded.results
    }

    private static func multipartBody(fileData: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"mimeType\"\r\n\r\n")
        append("\(mimeType)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}
