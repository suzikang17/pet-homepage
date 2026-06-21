// ios/PetHomepage/Features/Pairing/PairingService.swift
import Foundation

/// What a successful pairing returns: the minted mirror token + where to push snapshots.
struct PairResult: Equatable {
    let token: String
    let pushEndpoint: String
}

enum PairingError: Error, Equatable {
    case badStatus(Int)
    case badResponse
}

/// Exchanges a short pairing code (scanned from the dashboard QR, or typed) for a mirror
/// token via the Convex `/mirror/pair` httpAction. Injected so tests never hit the network.
protocol PairingService {
    func pair(code: String, endpoint: URL) async throws -> PairResult
}

enum PairingDefaults {
    /// This deployment's `/mirror/pair` endpoint, baked in so a *typed* code needs no URL from
    /// the user. QR pairing overrides this with the endpoint embedded in the scanned code, so a
    /// future deployment change still works by QR even before the app is rebuilt.
    static let pairEndpoint = URL(string: "https://industrious-grasshopper-402.convex.site/mirror/pair")!
}

/// The only PairingService that touches URLSession. POSTs `{ "code": ... }` and decodes
/// `{ "token", "push_endpoint" }` from the route.
final class URLSessionPairingService: PairingService {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func pair(code: String, endpoint: URL) async throws -> PairResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PairingError.badStatus(http.statusCode)
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = obj["token"] as? String, !token.isEmpty,
            let push = obj["push_endpoint"] as? String, !push.isEmpty
        else {
            throw PairingError.badResponse
        }
        return PairResult(token: token, pushEndpoint: push)
    }
}
