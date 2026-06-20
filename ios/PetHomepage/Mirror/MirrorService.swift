// ios/PetHomepage/Mirror/MirrorService.swift
import Foundation

/// Where the opt-in mirror endpoint lives, plus the per-user capability token the dashboard
/// minted. `endpoint` is the Convex httpAction URL (`<deployment>.convex.site/mirror/push`).
/// `token` is the opaque bearer token (nil/empty until the user pastes one into Settings).
struct MirrorConfig {
    let endpoint: URL
    let token: String?
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
        if let token = config.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Envelope the snapshot as { snapshot, schema_version } for the httpAction. Encode the
        // snapshot with MirrorSnapshot.encoder so its keys/dates stay identical to the dashboard
        // contract, then wrap it without re-encoding the inner object.
        let snapshotData = try MirrorSnapshot.encoder.encode(snapshot)
        let snapshotObject = try JSONSerialization.jsonObject(with: snapshotData)
        let envelope: [String: Any] = [
            "snapshot": snapshotObject,
            "schema_version": snapshot.schemaVersion,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MirrorError.badStatus(http.statusCode)
        }
    }
}
