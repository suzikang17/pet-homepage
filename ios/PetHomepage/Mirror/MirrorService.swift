// ios/PetHomepage/Mirror/MirrorService.swift
import Foundation

/// Where the opt-in mirror endpoint lives. The Convex sink + Next.js dashboard are DEFERRED —
/// this client is built entirely against the protocol below (tests use FakeMirrorService;
/// the production impl is exercised via a URLProtocol stub).
struct MirrorConfig {
    let endpoint: URL
}

enum MirrorError: Error, Equatable {
    case badStatus(Int)
}

/// Pushes a full MirrorSnapshot to the mirror sink. Injected everywhere so tests never hit
/// the network. A copy of the pet's records leaves iCloud when this runs — callers MUST gate
/// it behind the opt-in flag (see MirrorCoordinator).
protocol MirrorService {
    func push(_ snapshot: MirrorSnapshot) async throws
}

/// Production adapter: POSTs `MirrorSnapshot.encoder`-encoded JSON to a configurable URL.
/// The ONLY MirrorService that touches URLSession.
final class URLSessionMirrorService: MirrorService {
    private let config: MirrorConfig
    private let session: URLSession

    init(config: MirrorConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func push(_ snapshot: MirrorSnapshot) async throws {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try MirrorSnapshot.encoder.encode(snapshot)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MirrorError.badStatus(http.statusCode)
        }
    }
}
